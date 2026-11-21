import AppKit

/// Takes the keyboard without activating Notchcast while a caller holds it, and gives it back.
@MainActor
final class IslandKeyHold {
    private var panel: IslandKeyPanel?
    private var retry: Task<Void, Never>?
    private(set) var lease = IslandKeyLease()

    func hold(near shape: CGRect?, during notice: String,
              onFocus: @escaping @MainActor (Bool) -> Void, onKey: @escaping @MainActor (IslandHeldKey) -> Void) {
        release()
        lease.take(during: notice)
        let panel = panel ?? IslandKeyPanel()
        self.panel = panel
        move(near: shape)
        let focused = acquire(panel, onFocus: onFocus, onKey: onKey)
        if !focused { retake(onFocus: onFocus, onKey: onKey) }
        onFocus(focused)
    }

    func move(near shape: CGRect?) {
        guard lease.held, let shape else { return }
        panel?.setFrameOrigin(CGPoint(x: shape.midX, y: shape.midY))
    }

    private func acquire(_ panel: IslandKeyPanel, onFocus: @escaping @MainActor (Bool) -> Void,
                         onKey: @escaping @MainActor (IslandHeldKey) -> Void) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        guard panel.isKeyWindow else { return false }
        panel.onKey = onKey
        panel.onResign = { [weak self] in self?.retake(onFocus: onFocus, onKey: onKey) }
        return true
    }

    private func retake(onFocus: @escaping @MainActor (Bool) -> Void,
                        onKey: @escaping @MainActor (IslandHeldKey) -> Void) {
        retry = Task { [weak self] in
            guard !Task.isCancelled, let self, let panel else { return }
            retry = nil
            panel.orderOut(nil)
            let focused = acquire(panel, onFocus: onFocus, onKey: onKey)
            if !focused { release() }
            onFocus(focused)
        }
    }

    func noticesChanged(live: (String) -> Bool) {
        if lease.outlived(live: live) { release() }
    }

    func release() {
        retry?.cancel()
        retry = nil
        lease.give()
        panel?.onResign = nil
        panel?.onKey = nil
        panel?.orderOut(nil)
    }

    isolated deinit { release() }
}

/// Clear, one point square and mouse-transparent, so only its key focus is felt.
private final class IslandKeyPanel: NSPanel {
    var onKey: (@MainActor (IslandHeldKey) -> Void)?
    var onResign: (@MainActor () -> Void)?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onKey = nil
        guard let resigned = onResign else { return }
        onResign = nil
        resigned()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat, let onKey, let key = IslandHeldKey(keyCode: Int(event.keyCode)) {
            return onKey(key)
        }
        super.sendEvent(event)
    }
}
