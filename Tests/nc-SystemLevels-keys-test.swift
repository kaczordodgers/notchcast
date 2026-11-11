// notchcast-sources: Tinycast/Features/SystemLevels/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/MediaLevelKeyMonitor.swift
// notchcast-kit: input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

enum SystemLevelsService {
    enum Result {
        case applied(LevelNotice), fallbackToNativeKeys, cancelled
    }
}

@main @MainActor
struct MediaLevelKeysTests {
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    static func data(_ key: MediaLevelKey, down: Bool = true, repeat repeating: Bool = false) -> Int {
        (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8) | (repeating ? 1 : 0)
    }

    static func policyChecks() {
        let keys = Set(MediaLevelKey.allCases)
        for key in keys {
            var policy = MediaLevelKeyPolicy()
            func decide(_ down: Bool = true, repeat repeating: Bool = false, flags: UInt64 = 0)
                -> MediaLevelKeyPolicy.Decision {
                policy.decide(subtype: 8, data: data(key, down: down, repeat: repeating),
                              modifiers: flags, enabled: keys)
            }
            check(decide(false) == .pass, "Unowned releases pass")
            check(decide(repeat: true) == .pass, "Unowned repeats pass")
            for flags: UInt64 in [0x20000, 0x40000, 0x80000, 0x100000, 0x1E0000] {
                check(decide(flags: flags) == .pass, "Other shortcuts pass")
                check(decide(false) == .pass, "Other shortcuts keep their release")
            }
            check(decide() == .press(key, fine: false), "Plain key is a standard step")
            check(decide(repeat: true, flags: 0xA0000) == (key == .mute ? .swallow : .press(key, fine: true)),
                  "Repeats follow held ownership; mute toggles once")
            check(decide(false, flags: 0x100000) == .swallow, "Modifier changes cannot leak an owned release")
            check(decide(false) == .pass, "Release clears ownership")
            check(decide(flags: 0xA0000) == .press(key, fine: true), "Shift and Option select quarter steps")
            check(decide(false) == .swallow, "Fine release is owned")
            check(policy.decide(subtype: 8, data: data(key), modifiers: 0, enabled: []) == .pass,
                  "Disabled features pass untouched")
        }
        var policy = MediaLevelKeyPolicy()
        check(policy.decide(subtype: 7, data: data(.volumeUp), modifiers: 0, enabled: keys) == .pass,
              "Other system subtypes pass")
        check(policy.decide(subtype: 8, data: 16 << 16 | 0xA00, modifiers: 0, enabled: keys) == .pass,
              "Play and keyboard light keys pass")
        check(policy.decide(subtype: 8, data: 0xC00, modifiers: 0, enabled: keys) == .pass,
              "Unknown key states pass")
    }

    static func event(_ key: MediaLevelKey, down: Bool = true, repeat repeating: Bool = false,
                      flags: NSEvent.ModifierFlags = [], tagged: Bool = false) -> CGEvent {
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8,
            data1: data(key, down: down, repeat: repeating), data2: -1)?.cgEvent
        else { fatalError("Could not create an unposted media event") }
        if tagged { event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag) }
        return event
    }

    static func drain() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(10))
    }

    static func monitorChecks() async {
        let hub = EventTapHub()
        var presses: [MediaLevelKeyMonitor.Press] = []
        var notices: [LevelNotice] = []
        var replays: [MediaLevelKeyMonitor.Press] = []
        var result = SystemLevelsService.Result.applied(.init(kind: .volume, level: 0.5))
        var suspended: CheckedContinuation<Void, Never>?
        var block = false
        var executions: [MediaLevelKey] = []
        let monitor = MediaLevelKeyMonitor(hub: hub, prepare: { press in
            presses.append(press)
            return {
                executions.append(press.key)
                if block { await withCheckedContinuation { suspended = $0 } }
                return result
            }
        }, applied: { notices.append($0) }, replay: { replays.append($0) })
        monitor.setEnabled([.volumeUp, .volumeDown, .mute])
        check(hub.synchronousHandlers.count == 1 && hub.masks == [1 << 14],
              "Volume registers only system-defined events")
        let handler = hub.synchronousHandlers.values.first!
        let system = CGEventType(rawValue: 14)!
        check(handler(system, event(.brightnessUp)) == .pass, "Other feature passes")
        check(handler(system, event(.volumeUp, tagged: true)) == .pass, "Native replays cannot loop")
        check(handler(.keyDown, event(.volumeUp)) == .pass, "Non-media event types pass")
        check(handler(system, event(.volumeUp, flags: [.shift, .option])) == .swallow, "Press is swallowed synchronously")
        check(handler(system, event(.volumeUp, down: false)) == .swallow, "Release is swallowed synchronously")
        await drain()
        check(presses.count == 1 && presses[0].fine, "Decode sends one fine operation")
        check(notices.count == 1 && replays.isEmpty, "Success publishes without native HUD")
        let native = MediaLevelKeyMonitor.nativeEvents(for: presses[0])
        check(native.count == 2, "Native fallback is a complete press and release")
        for (index, event) in native.enumerated() {
            check(event.getIntegerValueField(.eventSourceUserData) == Paster.tinycastEventTag,
                  "Every replay event bypasses interception")
            check(NSEvent(cgEvent: event)?.data1 == data(.volumeUp, down: index == 0),
                  "Native fallback preserves the key and clears the repeat bit")
            check(event.flags.intersection([.maskShift, .maskAlternate]) == [.maskShift, .maskAlternate],
                  "Native fallback preserves fine-step modifiers")
        }
        result = .fallbackToNativeKeys
        check(handler(system, event(.volumeDown)) == .swallow, "Failed hardware starts intercepted")
        await drain()
        check(replays.count == 1 && replays[0].key == .volumeDown, "Failure replays the original key")
        _ = handler(system, event(.volumeDown, down: false))
        result = .cancelled
        _ = handler(system, event(.mute))
        _ = handler(system, event(.mute, repeat: true))
        await drain()
        check(presses.count == 3 && replays.count == 1, "Cancelled destinations do not replay; mute repeats do nothing")
        block = true
        _ = handler(system, event(.volumeUp))
        await drain()
        for _ in 0..<20 { _ = handler(system, event(.volumeUp, repeat: true)) }
        await drain()
        check(presses.count == 24, "All repeated events decode")
        block = false
        suspended?.resume()
        await drain()
        check(replays.count == 1, "Repeated cancelled commands do not replay")
        check(executions.count == 5, "Held repeats leave only one pending hardware operation")
        block = true
        result = .fallbackToNativeKeys
        _ = handler(system, event(.volumeDown))
        await drain()
        monitor.stop()
        suspended?.resume()
        await drain()
        check(hub.synchronousHandlers.isEmpty && replays.count == 1,
              "Stop removes the consumer and cancels late fallback")
        monitor.setEnabled([.brightnessUp])
        let brightness = hub.synchronousHandlers.values.first!
        _ = brightness(system, event(.brightnessUp))
        monitor.stop()
        await drain()
        check(presses.count == 25, "Already-dispatched callbacks cannot outlive registration")
    }

    static func brightnessChecks() async {
        let hub = EventTapHub()
        var presses: [MediaLevelKeyMonitor.Press] = []
        let monitor = MediaLevelKeyMonitor(hub: hub, prepare: { press in
            presses.append(press)
            return { .cancelled }
        }, applied: { _ in }, replay: { _ in })
        monitor.setEnabled([.brightnessUp, .brightnessDown])
        check(hub.masks == [(1 << 14) | (1 << 10) | (1 << 11)], "Brightness registers down and up")
        let handler = hub.synchronousHandlers.values.first!
        let system = CGEventType(rawValue: 14)!
        func keyboard(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            return event
        }
        for (code, key) in [(CGKeyCode(144), MediaLevelKey.brightnessUp), (145, .brightnessDown)] {
            var policy = MediaLevelKeyPolicy()
            let enabled: Set<MediaLevelKey> = [.brightnessUp, .brightnessDown]
            check(policy.decide(keyCode: Int(code), isDown: true, isRepeat: false,
                                modifiers: 0, enabled: []) == .pass, "Disabled keycodes pass")
            for flags: UInt64 in [0, 0xA0000] {
                let expected = MediaLevelKeyPolicy.Decision.press(key, fine: flags != 0)
                check(policy.decide(keyCode: Int(code), isDown: true, isRepeat: false,
                                    modifiers: flags, enabled: enabled) == expected, "Keycode step size")
                check(policy.decide(keyCode: Int(code), isDown: true, isRepeat: true,
                                    modifiers: flags, enabled: enabled) == expected, "Owned keycode repeats")
                check(policy.decide(keyCode: Int(code), isDown: false, isRepeat: false,
                                    modifiers: flags, enabled: enabled) == .swallow, "Keycode release owned")
            }
            for systemFirst in [false, true] {
                let first = systemFirst ? event(key) : keyboard(code, down: true)
                let second = systemFirst ? keyboard(code, down: true) : event(key)
                check(handler(systemFirst ? system : .keyDown, first) == .swallow, "First down owned")
                check(handler(systemFirst ? .keyDown : system, second) == .swallow, "Duplicate down swallowed")
                check(handler(.keyUp, keyboard(code, down: false)) == .swallow, "Paired key up owned")
                check(handler(system, event(key, down: false)) == .pass, "Duplicate release passes")
                await drain()
                check(presses.last?.key == key, "Keycode maps to the matching brightness key")
            }
            check(handler(.keyDown, keyboard(code, down: true, flags: .maskCommand)) == .pass,
                  "Command modified down passes")
            check(handler(.keyUp, keyboard(code, down: false, flags: .maskCommand)) == .pass,
                  "Command modified up passes")
        }
        for code: CGKeyCode in [0, 122, 160] {
            check(handler(.keyDown, keyboard(code, down: true)) == .pass, "Other key down passes")
            check(handler(.keyUp, keyboard(code, down: false)) == .pass, "Other key up passes")
        }
        await drain()
        check(presses.count == 4, "Each dual-delivered press executes exactly once")
        monitor.stop()
    }

    static func main() async {
        policyChecks()
        await monitorChecks()
        await brightnessChecks()
        print("PASS: \(checks) media-key checks; unposted events, no real hardware writes")
    }
}
