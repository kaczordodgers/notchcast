// notchcast-sources: Tinycast/Features/QuitProtection/Model/*.swift Tinycast/Features/QuitProtection/Service/*.swift
// notchcast-sources: Tinycast/Features/QuitProtection/QuitProtectionModule.swift
// notchcast-kit: platform input host
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }
enum ASCIIKeyboardLayout {
    @MainActor static func character(for code: Int, modifiers: UInt32) -> String? {
        code == 12 ? "q" : code == 13 ? "w" : nil
    }
}
@main @MainActor struct ModuleTests {
    static func main() {
        let suite = "nc.quit.module.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = EventTapHub()
        let store = QuitProtectionStore(defaults: defaults)
        store.configuration.mode = .doublePress
        var targetReads = 0
        var frontmost = QuitProtectionEngine.Target(processIdentifier: 42, bundleIdentifier: "test.app", name: "Test")
        var messages: [String] = []
        var posts: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        let module = QuitProtectionModule(store: store, hub: hub, frontmostTarget: {
            targetReads += 1
            return frontmost
        }, post: { pid, code in posts.append("\(pid):\(code)") })
        module.start()
        module.start()
        precondition(hub.consumerCount == 1)
        let idleReads = targetReads
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(targetReads == idleReads, "Idle protection must not poll the target")
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
        event.flags = .maskCommand
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
        precondition(hub.handler?(.keyDown, event) == .pass)
        do {
            let physical = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
            physical.flags = .maskCommand
            physical.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            precondition(hub.handler?(.keyDown, physical) == .swallow,
                         "code \(event.getIntegerValueField(.keyboardEventKeycode)) flags \(event.flags.rawValue)")
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        precondition(module.notice != nil)
        precondition(messages == [module.notice!.text], "The first swallowed press shows its hint once: \(messages)")
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.8))
        precondition(module.notice == nil, "Deadline must fire in tracking mode")
        func press(_ down: Bool) -> EventTapHub.Verdict? {
            let key = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: down)!
            key.flags = .maskCommand
            key.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            return hub.handler?(down ? .keyDown : .keyUp, key)
        }
        func doublePress() {
            precondition(press(true) == .swallow && press(false) == .swallow && press(true) == .swallow)
        }
        doublePress()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        precondition(posts == ["42:12"], "A confirmed double press posts Cmd+Q to the target once: \(posts)")
        _ = press(false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.7))
        doublePress()
        frontmost = .init(processIdentifier: 43, bundleIdentifier: "other.app", name: "Other")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        precondition(posts == ["42:12"], "A confirm whose target lost focus posts nothing: \(posts)")
        module.stop()
        module.stop()
        precondition(hub.consumerCount == 0 && module.notice == nil)
        print("PASS: module lifecycle, synchronous interception, synthetic bypass; no system effects")
    }
}

enum DialogTone { case neutral }
