// notchcast-sources: Tinycast/Features/HideCommandM/Model/*.swift
// notchcast-sources: Tinycast/Features/HideCommandM/Service/*.swift
// notchcast-kit: platform input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }

@main @MainActor
struct HideCommandMTests {
    static func main() {
        let hub = EventTapHub()
        let module = HideCommandMModule(hub: hub)
        func send(_ down: Bool = true, code: CGKeyCode = 46, flags: CGEventFlags = .maskCommand,
                  repeatKey: Bool = false, synthetic: Bool = false) -> EventTapHub.Verdict {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            if synthetic { event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag) }
            return hub.handler!(down ? .keyDown : .keyUp, event)
        }
        module.start()
        module.start()
        precondition(hub.consumerCount == 1, "Start twice registers once")
        precondition(send(code: 45) == .pass)
        precondition(send(flags: [.maskCommand, .maskShift]) == .pass)
        precondition(send(false) == .pass)
        precondition(send(synthetic: true) == .pass)
        precondition(send(repeatKey: true) == .pass)
        precondition(send(false) == .pass)
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let hides = pid > 0 && pid != ProcessInfo.processInfo.processIdentifier
        precondition((send() == .swallow) == hides, "A plain Command-M hides only another frontmost app")
        precondition(send(synthetic: true) == .pass, "Replayed keys pass even while one is held")
        precondition((send(flags: [.maskCommand, .maskShift], repeatKey: true) == .swallow) == hides)
        precondition((send(false, flags: []) == .swallow) == hides)
        precondition(send(false) == .pass)
        module.stop()
        module.stop()
        precondition(hub.consumerCount == 0 && hub.handler == nil)
        for pid: Int32 in [0, 1, 2] {
            for finder in [false, true] {
                for windows in [false, true] {
                    precondition(HideCommandMPolicy.shouldHide(pid: pid, ownPID: 1,
                        isFinder: finder, hasWindows: windows) == (pid == 2 && (!finder || windows)))
                }
            }
        }
        print("HideCommandM: all checks passed (press path \(hides ? "swallowed" : "passed, no other frontmost app"))")
    }
}
