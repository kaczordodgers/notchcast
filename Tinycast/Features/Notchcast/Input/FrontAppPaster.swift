import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

@MainActor
final class FrontAppPaster {
    enum Content {
        case text(String, rtf: Data? = nil)
        case image(Data)
        case files([URL])
    }

    enum Failure: Error {
        case busy
        case accessibilityUnavailable
        case targetUnavailable
        case clipboardUnavailable
        case eventUnavailable
        case restoreFailed
    }

    private let pasteboard: any PasteboardAccess
    private let isTrusted: () -> Bool
    private let frontmostPID: () -> pid_t?
    private let restoreDelay: Duration
    private var isPasting = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notchcast", category: "FrontAppPaster")

    init(
        pasteboard: any PasteboardAccess = NSPasteboard.general,
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        restoreDelay: Duration = .milliseconds(600)
    ) {
        self.pasteboard = pasteboard
        self.isTrusted = isTrusted
        self.frontmostPID = frontmostPID
        self.restoreDelay = restoreDelay
    }

    func paste(_ content: Content, into app: NSRunningApplication) async throws {
        guard !isPasting else { throw Failure.busy }
        guard isTrusted() else { throw Failure.accessibilityUnavailable }
        guard !app.isTerminated else { throw Failure.targetUnavailable }
        isPasting = true
        defer { isPasting = false }
        let pid = app.processIdentifier
        if frontmostPID() != pid { app.activate() }
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(500)
        while frontmostPID() != pid {
            guard clock.now < deadline, !app.isTerminated else { throw Failure.targetUnavailable }
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        guard isTrusted() else { throw Failure.accessibilityUnavailable }
        guard !app.isTerminated, frontmostPID() == pid else { throw Failure.targetUnavailable }
        guard let events = Self.pasteEvents() else { throw Failure.eventUnavailable }
        guard let original = PasteboardSnapshot(pasteboard: pasteboard),
            let saved = original.pasteboardItems(), let items = Self.items(for: content),
            pasteboard.changeCount == original.changeCount
        else { throw Failure.clipboardUnavailable }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            guard restore(saved) else { throw Failure.restoreFailed }
            throw Failure.clipboardUnavailable
        }
        let ownedChangeCount = pasteboard.changeCount
        // These events bypass session taps, including the hub and upstream's snippet listener.
        for event in events { event.post(tap: .cgAnnotatedSessionEventTap) }
        do {
            try await Task.sleep(for: restoreDelay)
        } catch {
            if pasteboard.changeCount == ownedChangeCount, !restore(saved) {
                logger.error("Could not restore the clipboard after cancelled paste")
            }
            throw error
        }
        guard pasteboard.changeCount == ownedChangeCount else { return }
        guard restore(saved) else { throw Failure.restoreFailed }
    }

    private func restore(_ items: [NSPasteboardItem]) -> Bool {
        pasteboard.clearContents()
        return items.isEmpty || pasteboard.writeObjects(items)
    }

    private static func items(for content: Content) -> [NSPasteboardItem]? {
        switch content {
        case .text(let text, let rtf):
            guard let item = PasteboardSnapshot.temporaryItem(carrying: text) else { return nil }
            if let rtf, !item.setData(rtf, forType: .rtf) { return nil }
            return [item]
        case .image(let data):
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .png),
                item.setData(Data(), forType: ClipboardManager.internalType)
            else { return nil }
            return [item]
        case .files(let urls):
            guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return nil }
            var items: [NSPasteboardItem] = []
            for url in urls {
                let item = NSPasteboardItem()
                guard item.setString(url.absoluteString, forType: .fileURL),
                    item.setData(Data(), forType: ClipboardManager.internalType)
                else { return nil }
                items.append(item)
            }
            return items
        }
    }

    private static func pasteEvents() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return nil }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
        }
        return [down, up]
    }
}
