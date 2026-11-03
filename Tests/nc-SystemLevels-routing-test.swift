// notchcast-sources: Tinycast/Features/SystemLevels/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelsModule.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelKeysModule.swift
// notchcast-sources: Tinycast/Features/SystemLevels/MediaLevelKeyMonitor.swift
// notchcast-sources: Tinycast/Features/DisplayBrightness/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import AppKit
import Synchronization

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
}

func CGDisplayBounds(_ display: UInt32) -> CGRect {
    CGRect(x: Int(display - 1) * 100, y: 0, width: 100, height: 100)
}

@MainActor
final class EventTapHub {
    enum Verdict { case pass, swallow }
    typealias SynchronousHandler = @Sendable (CGEventType, CGEvent) -> Verdict
    var handlers: [UUID: SynchronousHandler] = [:]

    func registerSynchronous(mask: CGEventMask, handler: @escaping SynchronousHandler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func remove(_ id: UUID) { handlers[id] = nil }
    func refreshPermission() {}

    func send(_ key: MediaLevelKey, fine: Bool = false, location: CGPoint = .init(x: 150, y: 50)) {
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: fine ? [.shift, .option] : [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
            data1: key.rawValue << 16 | 0xA00, data2: -1)?.cgEvent,
              let handler = handlers.values.first else { fatalError("Expected a registered handler") }
        event.location = location
        precondition(handler(CGEventType(rawValue: 14)!, event) == .swallow)
    }
}

@MainActor
final class DisplayBrightnessModule {
    @MainActor
    final class Controller {
        var entries = [BrightnessDisplay(id: .init(rawValue: 2, uuid: "external"), name: "Display",
                                         isBuiltIn: false, control: .ddc, level: .init(0.5))]
        var steps: [(Bool, Bool, BrightnessDisplay.ID)] = []
        func displays() -> [BrightnessDisplay] { entries }
        func step(up: Bool, fine: Bool, for display: BrightnessDisplay.ID) async -> BrightnessLevel? {
            steps.append((up, fine, display))
            guard let index = entries.firstIndex(where: { $0.id == display }) else { return nil }
            entries[index].level = entries[index].level.stepped(up: up, fine: fine)
            return entries[index].level
        }
    }
    let controller = Controller()
}

final class RoutingAudioHardware: SystemAudioHardware {
    struct State {
        var volume = 0.5
        var muted = false
        var writes = 0
    }
    let state = Mutex(State())
    func output() -> SystemAudioState.Output? {
        state.withLock { .init(device: 1, volume: $0.volume, muted: $0.muted) }
    }
    func microphone() -> SystemAudioState.Microphone? { nil }
    func writeVolume(_ volume: Double, device: UInt32) -> Bool {
        state.withLock { $0.volume = volume; $0.writes += 1 }
        return true
    }
    func writeMute(_ muted: Bool, device: UInt32) -> Bool {
        state.withLock { $0.muted = muted; $0.writes += 1 }
        return true
    }
}

@main @MainActor
struct SystemLevelRoutingTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    static func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        check(condition(), "Timed out waiting for routing")
    }

    static func main() async {
        let suite = "nc-keys-test-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let hub = EventTapHub()
        let hardware = RoutingAudioHardware()
        let levels = SystemLevelsModule(service: .init(hardware: hardware, observeHardware: false))
        let brightness = DisplayBrightnessModule()
        let keys = SystemLevelKeysModule(hub: hub, levels: levels, brightness: brightness, preferences: preferences)
        let controller = NotchcastModuleController([
            .init(requires: [.island, .volumeLevels], module: levels),
            .init(requires: [.island], module: keys),
        ], preferences: preferences)
        controller.run()
        await levels.service.settled()
        check(hub.handlers.count == 1, "One hub consumer handles both features")
        hub.send(.volumeUp)
        await eventually { keys.latest?.percent == 56 }
        check(hardware.state.withLock { $0.volume } == 9.0 / 16, "Standard key reaches the shipped audio service")
        hub.send(.volumeDown, fine: true)
        await eventually { keys.latest?.percent == 55 }
        check(hardware.state.withLock { $0.volume } == 35.0 / 64, "Fine key reaches the shipped audio policy")
        hub.send(.mute)
        await eventually { keys.latest?.muted == true }
        check(hardware.state.withLock { $0.muted }, "Mute key reaches audio hardware")
        hub.send(.brightnessUp, fine: true)
        await eventually { keys.latest?.kind == .brightness }
        check(keys.latest?.percent == 52, "Brightness state publishes the applied fine step")
        let step = brightness.controller.steps.first!
        check(step.0 && step.1 && step.2.rawValue == 2, "Brightness targets the display under the event pointer")
        check(keys.revision == 4, "Every applied press publishes a revision for island presentation")
        preferences.set(.volumeLevels, false)
        await eventually { !levels.service.isRunning && keys.latest == nil }
        check(hub.handlers.count == 1, "Brightness remains registered with volume off")
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 8, data1: 0xA00, data2: -1)!.cgEvent!
        check(hub.handlers.values.first!(CGEventType(rawValue: 14)!, event) == .pass,
              "Disabled volume passes untouched")
        preferences.set(.displayBrightness, false)
        await eventually { hub.handlers.isEmpty }
        preferences.set(.volumeLevels, true)
        preferences.set(.displayBrightness, true)
        await eventually { hub.handlers.count == 1 && levels.service.isRunning }
        let writes = hardware.state.withLock { $0.writes }
        hub.send(.volumeDown)
        preferences.set(.island, false)
        await eventually { hub.handlers.isEmpty && !levels.service.isRunning }
        check(hardware.state.withLock { $0.writes } == writes, "Disabling the island rejects already-dispatched keys")
        check(keys.latest == nil, "Off clears published key state")
        print("PASS: \(checks) routing checks; fake audio and displays, no real hardware writes")
    }
}
