// notchcast-sources: Tinycast/Features/SystemLevels/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelsModule.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelKeysModule.swift
// notchcast-sources: Tinycast/Features/SystemLevels/MediaLevelKeyMonitor.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelIslandPresenter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivityCenter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandValue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivityPresenter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandMessage.swift
// notchcast-sources: Tinycast/Features/DisplayBrightness/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
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
enum BrightnessDisplayService {
    static var available = true
    static func isAvailable(_ id: BrightnessDisplay.ID) -> Bool { available }
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
        let release = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8,
            data1: key.rawValue << 16 | 0xB00, data2: -1)!.cgEvent!
        precondition(handler(CGEventType(rawValue: 14)!, release) == .swallow)
    }
}

@MainActor
final class DisplayBrightnessModule {
    @MainActor
    final class Controller {
        enum StepResult { case applied(BrightnessLevel), unavailable, cancelled }
        var cancelStep = false
        var failStep = false
        var entries = [BrightnessDisplay(id: .init(rawValue: 2, uuid: "external"), name: "Display",
                                         isBuiltIn: false, control: .ddc, level: .init(0.5))]
        var steps: [(Bool, Bool, BrightnessDisplay.ID)] = []
        func displays() -> [BrightnessDisplay] { entries }
        func step(up: Bool, fine: Bool, for display: BrightnessDisplay.ID) async -> StepResult {
            steps.append((up, fine, display))
            if cancelStep { return .cancelled }
            if failStep { return .unavailable }
            guard let index = entries.firstIndex(where: { $0.id == display }) else { return .unavailable }
            entries[index].level = entries[index].level.stepped(up: up, fine: fine)
            return .applied(entries[index].level)
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
        while !condition() {
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
        let center = IslandActivityCenter()
        let presenter = SystemLevelIslandPresenter(center: center)
        var notices = 0
        var replays: [MediaLevelKeyMonitor.Press] = []
        let keys = SystemLevelKeysModule(hub: hub, levels: levels, brightness: brightness,
                                        preferences: preferences, present: {
            if $0 != nil { notices += 1 }
            presenter.present($0)
        }, replay: { replays.append($0) })
        let controller = NotchcastModuleController([
            .init(requires: [.island, .volumeLevels], module: levels),
            .init(requires: [], module: keys),
        ], preferences: preferences)
        controller.run()
        await levels.service.settled()
        check(hub.handlers.count == 1, "Brightness stays registered without a HUD presenter")
        check(hardware.state.withLock { $0.writes } == 0, "No presenter performs no custom steps")
        keys.hudPresenterAvailable = true
        check(hub.handlers.count == 1, "One hub consumer handles both features")
        hub.send(.volumeUp)
        await eventually { keys.latest?.percent == 56 }
        check(notices == 1, "Published notice reaches the presenter once")
        check(center.activities.count == 1 && center.current?.progress == 0.56,
              "First notice reaches the existing island progress activity")
        let activityID = center.current?.id
        check(hardware.state.withLock { $0.volume } == 9.0 / 16, "Standard key reaches the shipped audio service")
        hub.send(.volumeDown, fine: true)
        await eventually { keys.latest?.percent == 55 }
        check(notices == 2 && center.activities.count == 1 && center.current?.id == activityID,
              "Second notice replaces the first without stacking")
        check(center.current?.progress == 0.55, "Replacement carries the new progress")
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
        hub.send(.brightnessDown, location: .init(x: 500, y: 500))
        try? await Task.sleep(for: .milliseconds(50))
        check(replays.count == 1 && replays.last?.key == .brightnessDown,
              "Missing brightness target replays the native key")
        brightness.controller.failStep = true
        hub.send(.brightnessUp)
        try? await Task.sleep(for: .milliseconds(50))
        check(replays.count == 2, "Unavailable external brightness step replays the native key")
        brightness.controller.failStep = false
        BrightnessDisplayService.available = false
        hub.send(.brightnessDown)
        await eventually { brightness.controller.steps.count == 3 }
        for _ in 0..<20 { await Task.yield() }
        check(keys.revision == 4, "A disconnected or reused display cannot publish stale brightness")
        check(replays.count == 2, "A step already applied is never replayed to the native key")
        BrightnessDisplayService.available = true
        brightness.controller.cancelStep = true
        hub.send(.brightnessUp)
        await eventually { brightness.controller.steps.count == 4 }
        for _ in 0..<20 { await Task.yield() }
        check(keys.revision == 4, "Superseded brightness operations neither publish nor replay native keys")
        check(replays.count == 2, "Superseded brightness step stays cancelled")
        hub.send(.brightnessDown, location: .init(x: 500, y: 500))
        preferences.set(.displayBrightness, false)
        try? await Task.sleep(for: .milliseconds(50))
        check(replays.count == 2, "Switching brightness off cancels already-dispatched fallback")
        preferences.set(.displayBrightness, true)
        await eventually { hub.handlers.count == 1 }
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
        await eventually { hub.handlers.count == 1 && !levels.service.isRunning }
        check(hardware.state.withLock { $0.writes } == writes, "Disabling the island rejects already-dispatched keys")
        check(keys.latest == nil, "Off clears published key state")
        brightness.controller.cancelStep = false
        hub.send(.brightnessUp)
        await eventually { keys.latest?.kind == .brightness }
        check(keys.latest != nil, "Brightness works with the island off")
        keys.hudPresenterAvailable = false
        check(hub.handlers.count == 1, "Removing the presenter keeps brightness registered")
        check(center.activities.isEmpty, "Removing the presenter clears its activity")
        print("PASS: \(checks) routing checks; fake audio and displays, no real hardware writes")
    }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = CommandIndexFixture()
}
@MainActor final class CommandIndexFixture {
    private(set) var refreshes = 0
    func refreshNotchcastCommands() { refreshes += 1 }
}
