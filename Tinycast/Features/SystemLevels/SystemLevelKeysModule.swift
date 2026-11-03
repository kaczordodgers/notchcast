import CoreGraphics
import Observation

@MainActor @Observable
final class SystemLevelKeysModule: NotchcastModule {
    private(set) var latest: LevelNotice?
    private(set) var revision = 0
    @ObservationIgnored private let levels: SystemLevelsModule
    @ObservationIgnored private let brightness: DisplayBrightnessModule
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let hub: EventTapHub
    @ObservationIgnored private var running = false
    @ObservationIgnored private lazy var monitor = MediaLevelKeyMonitor(
        hub: hub, prepare: { [weak self] press in
            self?.prepare(press) ?? { .cancelled }
        }, applied: { [weak self] notice in self?.publish(notice) })

    init(hub: EventTapHub, levels: SystemLevelsModule, brightness: DisplayBrightnessModule,
         preferences: NotchcastPreferences = .shared) {
        self.hub = hub
        self.levels = levels
        self.brightness = brightness
        self.preferences = preferences
    }

    func start() {
        guard !running else { return }
        running = true
        observeSwitches()
    }

    func stop() {
        running = false
        monitor.stop()
        latest = nil
    }

    private func publish(_ notice: LevelNotice) {
        latest = notice
        revision += 1
    }

    private func observeSwitches() {
        guard running else { return }
        withObservationTracking {
            let island = preferences.isOn(.island)
            let volume = preferences.isOn(.volumeLevels)
            let display = preferences.isOn(.displayBrightness)
            let keys = Set(MediaLevelKey.allCases.filter { island && ($0.isBrightness ? display : volume) })
            monitor.setEnabled(keys)
            latest = nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeSwitches() }
        }
    }

    private func prepare(_ press: MediaLevelKeyMonitor.Press) -> MediaLevelKeyMonitor.Operation {
        guard preferences.isOn(.island),
              preferences.isOn(press.key.isBrightness ? .displayBrightness : .volumeLevels)
        else { return { .cancelled } }
        if press.key.isBrightness {
            let controller = brightness.controller
            let preferences = preferences
            guard let display = controller.displays().first(where: {
                CGDisplayBounds($0.id.rawValue).contains(press.location)
            }) else { return { .fallbackToNativeKeys } }
            return {
                guard !Task.isCancelled, preferences.isOn(.island), preferences.isOn(.displayBrightness)
                else { return .cancelled }
                let level = await controller.step(up: press.key.isIncreasing, fine: press.fine, for: display.id)
                guard !Task.isCancelled, controller.displays().contains(where: { $0.id == display.id })
                else { return .cancelled }
                guard let level else { return .fallbackToNativeKeys }
                return .applied(LevelNotice(kind: .brightness, level: level.value))
            }
        }
        let service = levels.service
        let preferences = preferences
        return {
            guard !Task.isCancelled, service.isRunning,
                  preferences.isOn(.island), preferences.isOn(.volumeLevels) else { return .cancelled }
            return await service.apply(press.key == .mute ? .toggleMute
                : .step(increasing: press.key.isIncreasing, fine: press.fine))
        }
    }
}
