import AppKit
import ApplicationServices

@MainActor
final class NotificationCleanupObserver {
    private var observer: AXObserver?
    private var pid: pid_t?
    private var timer: Timer?
    private let policy = NotificationCleanupPolicy(diskEjectionTitles: [
        "Disk Not Ejected Properly", "Dysk nie został wysunięty prawidłowo"
    ])

    func start() {
        stop()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detach()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        pid = nil
    }

    func update() {
        guard NotchcastPreferences.shared.isOn(.notificationCleanup), AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui").first else {
            detach()
            return
        }
        guard pid != app.processIdentifier else { return }
        detach()
        var created: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { _, _, _, context in
            guard let context else { return }
            let owner = Unmanaged<NotificationCleanupObserver>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak owner] in owner?.sweep() }
        }, &created)
        guard result == .success, let created else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, root, notification as CFString, context)
        }
        observer = created
        pid = app.processIdentifier
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        sweep()
    }

    private func sweep() {
        guard NotchcastPreferences.shared.isOn(.notificationCleanup), AXIsProcessTrusted(), let pid else {
            detach()
            return
        }
        let root = AXUIElementCreateApplication(pid)
        for _ in 0..<100 {
            guard let element = selected(in: root, depth: 0), let alert = snapshot(element) else { return }
            do {
                guard try NotificationCleanupService(policy: policy).apply(
                    alerts: [alert], trusted: true, current: { _ in snapshot(element) }, perform: { _, action in
                        let result = AXUIElementPerformAction(element, action as CFString)
                        guard result == .success else {
                            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result.rawValue))
                        }
                    }) == 1 else { return }
            } catch { return }
        }
    }

    private func selected(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 20 else { return nil }
        if let alert = snapshot(element), policy.closeAction(for: alert) != nil { return element }
        for child in children(element) {
            if let selected = selected(in: child, depth: depth + 1) { return selected }
        }
        return nil
    }

    private func snapshot(_ element: AXUIElement) -> NotificationCleanupPolicy.Alert? {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let names = actions as? [String],
              let subrole = string(element, kAXSubroleAttribute),
              subrole.lowercased().contains("notificationcenter") else { return nil }
        let titles = [string(element, kAXTitleAttribute)] + children(element).map {
            string($0, kAXValueAttribute) ?? string($0, kAXTitleAttribute)
        }
        guard let title = titles.compactMap({ $0 }).first(where: policy.diskEjectionTitles.contains) else { return nil }
        return .init(identifier: title, title: title,
                     isIndividualAlert: !names.contains(where: { $0.hasPrefix("Name:Clear All") }), actions: names)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
