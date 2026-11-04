import AppKit
import Carbon.HIToolbox
import os
import Observation

@MainActor
@Observable
final class PasteImageModule: NotchcastModule {
    private(set) var saveFailed = false
    private let hub: EventTapHub
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var activation: NotificationToken?
    var onFailure: (() -> Void)?
    private var work: Task<Void, Never>?
    private var token: UUID?

    private struct State: Sendable {
        var eligible = false
        var changeCount: Int?
        var acceptsImage = false
        var filter = PasteImagePolicy()
    }

    init(hub: EventTapHub) { self.hub = hub }

    func start() {
        guard token == nil else { return }
        let state = state
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        token = hub.registerSynchronous(mask: mask) { [weak self] type, event in
            guard event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_V,
                event.getIntegerValueField(.eventSourceUserData) != Paster.tinycastEventTag
            else { return .pass }
            let repeatKey = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
            let commandOnly = event.flags.intersection(modifiers) == .maskCommand
            let take = state.withLock { state in
                let board = NSPasteboard.general
                if state.changeCount != board.changeCount {
                    state.changeCount = board.changeCount
                    state.acceptsImage = PasteImagePolicy.accepts(types: board.types?.map(\.rawValue) ?? [])
                }
                return state.filter.take(down: type == .keyDown, repeatKey: repeatKey,
                    eligible: state.eligible && state.acceptsImage && commandOnly)
            }
            guard take else { return .pass }
            if type == .keyDown && !repeatKey {
                Task { @MainActor [weak self] in self?.paste() }
            }
            return .swallow
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
        if let token { hub.remove(token) }
        token = nil
        state.withLock { $0 = State() }
    }

    private func updateEligibility() {
        let eligible = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        state.withLock { $0.eligible = eligible }
        hub.refreshPermission()
    }

    func paste() {
        guard token != nil else { return }
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
