// notchcast-sources: Tinycast/Features/ShowDesktop/Service/*.swift
// notchcast-kit: input
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }
enum Paster { static let tinycastEventTag: Int64 = 1 }

@MainActor final class EventTapHub {
    struct Event {}
    enum Verdict { case pass, swallow }
    var handler: (@Sendable (CGEventType, CGEvent) -> Verdict)?
    var count = 0
    func registerSynchronous(mask: CGEventMask,
                             handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict) -> UUID {
        precondition(mask != 0)
        self.handler = handler
        count += 1
        return UUID()
    }
    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID { UUID() }
    func remove(_ id: UUID) { count -= 1; handler = nil }
}

@main @MainActor
struct ShowDesktopTests {
    static func main() {
        let hub = EventTapHub()
        let module = ShowDesktopModule(hub: hub)
        func send(_ down: Bool, _ code: CGKeyCode = 160, modifiers: CGEventFlags = [],
                  repeatKey: Bool = false) -> EventTapHub.Verdict {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = modifiers
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            return hub.handler!(down ? .keyDown : .keyUp, event)
        }
        module.start()
        module.start()
        precondition(hub.count == 1, "Start twice registers once")
        precondition(send(false) == .pass)
        precondition(send(true, 42) == .pass)
        precondition(send(true, modifiers: .maskCommand) == .pass)
        precondition(send(true, repeatKey: true) == .pass)
        precondition(send(false) == .pass)
        for _ in 0..<2 {
            precondition(send(true) == .swallow, "A plain press toggles")
            precondition(send(true, modifiers: .maskShift, repeatKey: true) == .swallow)
            precondition(send(false, 42) == .pass)
            precondition(send(false, modifiers: .maskShift) == .swallow, "Its release is swallowed too")
            precondition(send(false) == .pass)
        }
        module.stop()
        module.stop()
        precondition(hub.count == 0 && hub.handler == nil)
        module.start()
        precondition(hub.count == 1)
        module.stop()
        print("Show desktop: all checks passed")
    }
}
