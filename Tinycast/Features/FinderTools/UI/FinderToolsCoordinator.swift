import AppKit
import Observation

@MainActor @Observable
final class FinderToolsCoordinator {
    private var cutSession = FinderCutSession()
    @ObservationIgnored private let hub: EventTapHub
    @ObservationIgnored private let input = FinderShortcutState()
    @ObservationIgnored private var registration: UUID?
    @ObservationIgnored private var activation: NotificationToken?
    @ObservationIgnored private var operation: Task<Void, Never>?
    private var cutEnabled = false
    private var renameEnabled = false
    private var permissionGranted = false

    init(hub: EventTapHub) { self.hub = hub }

    isolated deinit {
        operation?.cancel()
        if let registration { hub.remove(registration) }
    }

    func setEnabled(_ feature: NotchcastFeature, _ enabled: Bool) {
        if feature == .finderCutPaste { cutEnabled = enabled }
        if feature == .finderRename { renameEnabled = enabled }
        operation?.cancel()
        operation = nil
        cutSession.clear()
        input.configure(cut: cutEnabled, rename: renameEnabled, pid: finderPID)
        if cutEnabled || renameEnabled { start() } else { stop() }
    }

    func cut() { perform(keyCode: 7, modifiers: .command) }
    func paste() { perform(keyCode: 9, modifiers: .command) }
    func rename() { perform(keyCode: 15, modifiers: .hyper) }

    private var finderPID: Int32? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.bundleIdentifier == "com.apple.finder" ? app?.processIdentifier : nil
    }

    private func perform(keyCode: Int64, modifiers: FinderShortcutPolicy.Modifiers) {
        guard AXIsProcessTrusted() else { return }
        refreshContext()
        let (_, request) = input.receive(.init(keyCode: keyCode, modifiers: modifiers))
        _ = input.receive(.init(keyCode: keyCode, modifiers: modifiers, isKeyDown: false))
        if let request { enqueue(request) }
    }

    private func start() {
        guard registration == nil else { return }
        permissionGranted = AXIsProcessTrusted()
        let input = input
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
        registration = hub.registerSynchronous(mask: mask) { [weak self] type, event in
            let flags = event.flags
            var modifiers: FinderShortcutPolicy.Modifiers = []
            if flags.contains(.maskCommand) { modifiers.insert(.command) }
            if flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if flags.contains(.maskControl) { modifiers.insert(.control) }
            if flags.contains(.maskShift) { modifiers.insert(.shift) }
            let (decision, request) = input.receive(.init(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode), modifiers: modifiers,
                isKeyDown: type == .keyDown, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                isSynthetic: event.getIntegerValueField(.eventSourceUserData) == Paster.tinycastEventTag))
            if let request {
                DispatchQueue.main.async { [weak self] in self?.enqueue(request) }
            }
            return decision == .pass || decision == .perform(.forget) ? .pass : .swallow
        }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshContext()
            }
        }, center: center)
    }

    private func stop() {
        if let registration { hub.remove(registration) }
        registration = nil
        activation = nil
    }

    private func enqueue(_ request: FinderShortcutState.Request) {
        if request.action == .forget {
            if input.isCurrentCut(request) { cutSession.clear() }
            return
        }
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.isCurrent(request) else { return }
            let focus = await FinderCommandService.focus(pid: request.pid)
            guard !Task.isCancelled, self.isCurrent(request) else { return }
            if focus == .text {
                self.forwardText(request)
                return
            }
            guard focus == .files else {
                self.cutSession.clear()
                self.input.finishCut(request)
                self.forwardUnavailable(request)
                return
            }
            switch request.action {
            case .cut: await self.copySelection(request)
            case .paste: self.moveSelection(request)
            case .rename: FinderCommandService.post(keyCode: 36, flags: [], pid: request.pid)
            case .forget: break
            }
        }
    }

    private func refreshContext() {
        input.setFrontmostFinder(finderPID)
        if let count = cutSession.clipboardChangeCount, count != NSPasteboard.general.changeCount {
            cutSession.clear()
            input.forgetCut()
        }
        let granted = AXIsProcessTrusted()
        guard permissionGranted != granted else { return }
        permissionGranted = granted
        operation?.cancel()
        cutSession.clear()
        input.configure(cut: cutEnabled, rename: renameEnabled, pid: finderPID)
        hub.refreshPermission()
    }

    private func isCurrent(_ request: FinderShortcutState.Request) -> Bool {
        AXIsProcessTrusted() && finderPID == request.pid && input.isCurrent(request)
    }

    private func forwardText(_ request: FinderShortcutState.Request) {
        switch request.action {
        case .cut:
            cutSession.clear()
            input.finishCut(request)
            FinderCommandService.post(keyCode: 7, flags: .maskCommand, pid: request.pid)
        case .paste:
            input.restoreCut(request)
            FinderCommandService.post(keyCode: 9, flags: .maskCommand, pid: request.pid)
        case .rename, .forget: break
        }
    }

    private func forwardUnavailable(_ request: FinderShortcutState.Request) {
        guard let (key, flags) = FinderCommandService.originalKey(for: request.action) else { return }
        FinderCommandService.post(keyCode: key, flags: flags, pid: request.pid)
    }

    private func copySelection(_ request: FinderShortcutState.Request) async {
        cutSession.clear()
        let before = NSPasteboard.general.changeCount
        FinderCommandService.post(keyCode: 8, flags: .maskCommand, pid: request.pid)
        for _ in 0..<25 {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            guard isCurrent(request) else { return }
            let clipboard = NSPasteboard.general
            let copiedChangeCount = clipboard.changeCount
            guard copiedChangeCount != before else { continue }
            let files = clipboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
            guard clipboard.changeCount == copiedChangeCount else {
                input.finishCut(request)
                return
            }
            cutSession.mark(changeCount: copiedChangeCount, fileCount: files.count)
            if files.isEmpty { input.finishCut(request) }
            return
        }
        input.finishCut(request)
    }

    private func moveSelection(_ request: FinderShortcutState.Request) {
        let move = cutSession.take(changeCount: NSPasteboard.general.changeCount)
        input.finishCut(request)
        FinderCommandService.post(keyCode: 9, flags: move ? [.maskCommand, .maskAlternate] : .maskCommand,
                                  pid: request.pid)
    }
}
