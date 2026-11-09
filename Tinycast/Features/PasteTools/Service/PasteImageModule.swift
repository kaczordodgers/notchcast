import AppKit
import Carbon.HIToolbox
import os
import Observation

@MainActor
@Observable
final class PasteImageModule: NotchcastModule {
    private(set) var saveFailed = false
    private let tap: EventTapSubscription
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var activation: NotificationToken?
    var onFailure: (() -> Void)?
    private var work: Task<Void, Never>?

    private struct State: Sendable {
        var eligible = false
        var changeCount: Int?
        var acceptsImage = false
    }

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
        let state = state
        let pasteboard = pasteboard
        tap.startKeyPress(Int64(kVK_ANSI_V), skipsSynthetic: true) { [weak self] event in
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
            guard event.flags.intersection(modifiers) == .maskCommand else { return false }
            let take = state.withLock { state in
                let board = NSPasteboard(name: pasteboard)
                if state.changeCount != board.changeCount {
                    state.changeCount = board.changeCount
                    state.acceptsImage = PasteImagePolicy.accepts(types: board.types?.map(\.rawValue) ?? [])
                }
                return state.eligible && state.acceptsImage
            }
            if take { Task { @MainActor [weak self] in self?.paste() } }
            return take
        }
        updateEligibility()
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateEligibility() }
        }, center: center)
    }

    func stop() {
        activation = nil
        work?.cancel()
        work = nil
        tap.stop()
        state.withLock { $0 = State() }
    }

    private func updateEligibility() {
        let eligible = finderIsFrontmost()
        state.withLock { $0.eligible = eligible }
    }

    func paste() {
        guard tap.isActive else { return }
        guard work == nil else { Paster.postCommandV(); return }
        saveFailed = false
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier == "com.apple.finder",
            PasteImagePolicy.accepts(types: NSPasteboard.general.types?.map(\.rawValue) ?? [])
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
        let board = NSPasteboard.general
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
