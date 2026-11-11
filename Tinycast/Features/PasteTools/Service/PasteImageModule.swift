import AppKit
import Carbon.HIToolbox
import os
import Observation

@MainActor
@Observable
final class PasteImageModule: NotchcastModule {
    private(set) var saveFailed = false
    private let tap: EventTapSubscription
    private let takes = OSAllocatedUnfairLock(initialState: false)
    private var activation: NotificationToken?
    private var ticker: Task<Void, Never>?
    private var changeCount: Int?
    var onFailure: (() -> Void)?
    private var work: Task<Void, Never>?

    private let pasteboard: NSPasteboard.Name
    private let finderIsFrontmost: @MainActor () -> Bool

    init(hub: EventTapHub, pasteboard: NSPasteboard.Name = .general,
         finderIsFrontmost: @escaping @MainActor () -> Bool = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
         }) {
        tap = EventTapSubscription(hub: hub)
        self.pasteboard = pasteboard
        self.finderIsFrontmost = finderIsFrontmost
    }

    func start() {
        guard !tap.isActive else { return }
        let takes = takes
        // The tap thread reads only this flag; the main actor keeps it current from the pasteboard.
        tap.startKeyPress(Int64(kVK_ANSI_V), skipsSynthetic: true) { [weak self] event in
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
            guard event.flags.intersection(modifiers) == .maskCommand, takes.withLock({ $0 }) else { return false }
            Task { @MainActor [weak self] in self?.paste() }
            return true
        }
        frontmostChanged()
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.frontmostChanged() }
        }, center: center)
    }

    func stop() {
        activation = nil
        work?.cancel()
        work = nil
        tap.stop()
        stopTicking()
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
        changeCount = nil
        takes.withLock { $0 = false }
    }

    private func frontmostChanged() {
        guard tap.isActive else { return }
        stopTicking()
        guard finderIsFrontmost() else { return }
        ticker = Task { [weak self] in
            while true {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.clipboardTick()
            }
        }
        clipboardTick()
    }

    func clipboardTick() {
        let board = NSPasteboard(name: pasteboard)
        guard ticker != nil, board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        let accepts = PasteImagePolicy.accepts(types: board.types?.map(\.rawValue) ?? [])
        takes.withLock { $0 = accepts }
    }

    func paste() {
        guard tap.isActive else { return }
        guard work == nil else { Paster.postCommandV(); return }
        saveFailed = false
        let board = NSPasteboard(name: pasteboard)
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier == "com.apple.finder",
            PasteImagePolicy.accepts(types: board.types?.map(\.rawValue) ?? [])
        else { Paster.postCommandV(); return }
        let finder = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(finder, kAXFocusedUIElementAttribute as CFString, &focused)
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            var role: CFTypeRef?
            let element = unsafeDowncast(focused, to: AXUIElement.self)
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if role as? String == kAXTextFieldRole || role as? String == kAXTextAreaRole {
                Paster.postCommandV()
                return
            }
        }
        guard let type = board.availableType(from: [.png, .tiff, .init("public.jpeg"), .init("public.heic")]),
            let data = board.data(forType: type)
        else { Paster.postCommandV(); return }
        let isPNG = type == .png
        work = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return false }
                guard let png = isPNG ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                else { return false }
                return FinderImageService.save(png)
            }
            let saved = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self else { return }
            self.work = nil
            self.saveFailed = !saved
            if !saved { self.onFailure?() }
        }
    }
}
