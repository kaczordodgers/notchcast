// notchcast-sources: Tinycast/Features/SystemLevels/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelsModule.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelKeysModule.swift
// notchcast-sources: Tinycast/Features/SystemLevels/MediaLevelKeyMonitor.swift
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

func CGDisplayBounds(_ display: UInt32) -> CGRect { .zero }

@MainActor
enum BrightnessDisplayService {
    static func isAvailable(_ id: BrightnessDisplay.ID) -> Bool { true }
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
}

@MainActor
final class DisplayBrightnessModule {
    @MainActor
    final class Controller {
        enum StepResult { case applied(BrightnessLevel), unavailable, cancelled }
        func displays() -> [BrightnessDisplay] { [] }
        func step(up: Bool, fine: Bool, for display: BrightnessDisplay.ID) async -> StepResult { .cancelled }
    }
    let controller = Controller()
}

final class SilentAudioHardware: SystemAudioHardware {
    func output() -> SystemAudioState.Output? { nil }
    func microphone() -> SystemAudioState.Microphone? { nil }
    func writeVolume(_ volume: Double, device: UInt32) -> Bool { false }
    func writeMute(_ muted: Bool, device: UInt32) -> Bool { false }
}

@main @MainActor
struct SystemLevelObservationTests {
    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    static func main() async {
        let suite = "nc-levels-observation-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let levels = SystemLevelsModule(service: .init(hardware: SilentAudioHardware(), observeHardware: false))
        var bodyRuns = 0
        let keys = SystemLevelKeysModule(hub: EventTapHub(), levels: levels, brightness: DisplayBrightnessModule(),
                                        preferences: preferences, present: { if $0 == nil { bodyRuns += 1 } })
        func runsAfterPreferenceChange() async -> Int {
            await settle()
            bodyRuns = 0
            preferences.set(.volumeLevels, !preferences.isOn(.volumeLevels))
            await settle()
            return bodyRuns
        }
        keys.start()
        let baseline = await runsAfterPreferenceChange()
        precondition(baseline == 1, "One live chain re-runs once per change, got \(baseline)")
        for _ in 0..<10 {
            keys.hudPresenterAvailable = true
            keys.hudPresenterAvailable = false
            await settle()
        }
        let afterFlips = await runsAfterPreferenceChange()
        precondition(afterFlips == 1, "Presenter flips must not add chains: 1 run expected, got \(afterFlips)")
        keys.stop()
        keys.start()
        keys.stop()
        keys.start()
        let afterRestart = await runsAfterPreferenceChange()
        precondition(afterRestart == 1, "Stop must end its chain: 1 run expected, got \(afterRestart)")
        keys.stop()
        let afterStop = await runsAfterPreferenceChange()
        precondition(afterStop == 0, "A stopped module must not re-run, got \(afterStop)")
        print("PASS: one observation chain across presenter flips and stop/start")
    }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = CommandIndexFixture()
}
@MainActor final class CommandIndexFixture {
    func refreshNotchcastCommands() {}
}
