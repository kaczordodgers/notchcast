import CoreGraphics
import Observation

@MainActor @Observable
final class SystemLevelKeysModule: NotchcastModule {
    private(set) var latest: LevelNotice?
    private(set) var revision = 0
    @ObservationIgnored private let center: IslandActivityCenter
    @ObservationIgnored private let levels: SystemLevelsModule
    @ObservationIgnored private let brightness: DisplayBrightnessModule
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let hub: EventTapHub
    @ObservationIgnored private let present: (LevelNotice?) -> Void
    @ObservationIgnored private let replay: @MainActor (MediaLevelKeyMonitor.Press) -> Void
    @ObservationIgnored private var running = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private lazy var monitor = MediaLevelKeyMonitor(
        hub: hub, prepare: { [weak self] press in
            self?.prepare(press) ?? { .cancelled }
        }, applied: { [weak self] notice in self?.publish(notice) }, replay: replay)

    init(hub: EventTapHub, levels: SystemLevelsModule, brightness: DisplayBrightnessModule,
         preferences: NotchcastPreferences = .shared, center: IslandActivityCenter = .shared,
         present: @escaping (LevelNotice?) -> Void = { _ in },
         replay: @escaping @MainActor (MediaLevelKeyMonitor.Press) -> Void = MediaLevelKeyMonitor.replay) {
        self.hub = hub
        self.center = center
        self.levels = levels
        self.brightness = brightness
        self.preferences = preferences
        self.present = present
        self.replay = replay
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
        present(nil)
    }

    private func publish(_ notice: LevelNotice) {
        latest = notice
        revision += 1
        present(notice)
    }

    private func observeSwitches() {
        guard running else { return }
        generation += 1
        let current = generation
        withObservationTracking {
            let island = preferences.isOn(.island)
            let volume = preferences.isOn(.volumeLevels)
            let display = preferences.isOn(.displayBrightness)
            let presenter = hudPresenterAvailable
            let keys = Set(MediaLevelKey.allCases.filter {
                $0.isBrightness ? display : presenter && island && volume
            })
            monitor.setEnabled(keys)
            latest = nil
            if !presenter { present(nil) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == current else { return }
                observeSwitches()
            }
        }
    }

    private var hudPresenterAvailable: Bool {
        center.hasPresenter && preferences.isOn(.islandLiveActivities)
    }

    private func prepare(_ press: MediaLevelKeyMonitor.Press) -> MediaLevelKeyMonitor.Operation {
        guard press.key.isBrightness || (hudPresenterAvailable && preferences.isOn(.island)),
              preferences.isOn(press.key.isBrightness ? .displayBrightness : .volumeLevels)
        else { return { .cancelled } }
        if press.key.isBrightness {
            let controller = brightness.controller
            let preferences = preferences
            guard let display = controller.displays().first(where: {
                CGDisplayBounds($0.id.rawValue).contains(press.location)
            }) else {
                return {
                    guard !Task.isCancelled, preferences.isOn(.displayBrightness) else { return .cancelled }
                    return .fallbackToNativeKeys
                }
            }
            return {
                guard !Task.isCancelled, preferences.isOn(.displayBrightness)
                else { return .cancelled }
                let result = await controller.step(up: press.key.isIncreasing, fine: press.fine, for: display.id)
                guard !Task.isCancelled, preferences.isOn(.displayBrightness)
                else { return .cancelled }
                switch result {
                case .applied(let level):
                    guard BrightnessDisplayService.isAvailable(display.id),
                          controller.displays().contains(where: { $0.id == display.id })
                    else { return .cancelled }
                    return .applied(LevelNotice(kind: .brightness, level: level.value))
                case .unavailable: return .fallbackToNativeKeys
                case .cancelled: return .cancelled
                }
            }
        }
        let service = levels.service
        let preferences = preferences
        return {
            guard !Task.isCancelled, service.isRunning,
                  preferences.isOn(.island), preferences.isOn(.volumeLevels) else { return .cancelled }
            let result = await service.apply(press.key == .mute ? .toggleMute
                : .step(increasing: press.key.isIncreasing, fine: press.fine))
            guard !Task.isCancelled, preferences.isOn(.island), preferences.isOn(.volumeLevels)
            else { return .cancelled }
            return result
        }
    }
}
