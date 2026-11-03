import Foundation

struct IslandInputState: Sendable {
    enum Dismissal { case outsideClick, appSwitch, mouseOut, escape, pageKey }
    enum HoverAction: Sendable { case open, close }
    struct PendingHover: Equatable, Sendable {
        let action: HoverAction
        let deadline: TimeInterval
    }

    private(set) var isOpen = false
    private(set) var isPinned = false
    private(set) var pointerInside = false
    private(set) var pendingHover: PendingHover?

    mutating func open() {
        pendingHover = nil
        isOpen = true
    }

    mutating func dismiss(_ reason: Dismissal, focused: Bool = false) {
        guard reason != .mouseOut || !focused else { return }
        guard !isPinned || reason == .escape || reason == .pageKey else { return }
        close()
    }

    mutating func close() {
        pendingHover = nil
        isOpen = false
        isPinned = false
    }

    mutating func togglePin() {
        guard isOpen else { return }
        if isPinned { close() } else {
            pendingHover = nil
            isPinned = true
        }
    }

    mutating func setPinned(_ pinned: Bool) {
        isPinned = isOpen && pinned
        if isPinned { pendingHover = nil }
    }

    mutating func pointer(inside: Bool, now: TimeInterval, hoverEnabled: Bool, delay: TimeInterval) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        pendingHover = nil
        if inside, !isOpen, hoverEnabled {
            pendingHover = .init(action: .open, deadline: now + delay)
        } else if !inside, isOpen, !isPinned {
            pendingHover = .init(action: .close, deadline: now + 0.3)
        }
    }

    mutating func cancelHoverOpen() {
        if pendingHover?.action == .open { pendingHover = nil }
    }

    mutating func advance(now: TimeInterval, focused: Bool = false) -> HoverAction? {
        guard let pendingHover, now >= pendingHover.deadline else { return nil }
        self.pendingHover = nil
        switch pendingHover.action {
        case .open:
            guard pointerInside, !isOpen else { return nil }
            open()
        case .close:
            guard !pointerInside, isOpen, !isPinned, !focused else { return nil }
            dismiss(.mouseOut)
        }
        return pendingHover.action
    }
}
