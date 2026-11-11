// notchcast-sources: Tinycast/Features/ShowDesktop/Service/*.swift
// notchcast-kit: input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }

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
        precondition(hub.consumerCount == 1, "Start twice registers once")
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
        precondition(hub.consumerCount == 0 && hub.handler == nil)
        module.start()
        precondition(hub.consumerCount == 1)
        module.stop()
        print("Show desktop: all checks passed")
    }
}
