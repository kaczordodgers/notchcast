import Foundation

enum TreadmillCommands {
    nonisolated static let start = command("walk-start", "Start Walk", action: .start)
    nonisolated static let stop = command("walk-stop", "Stop Walk", action: .stop)
    nonisolated static let pause = command("walk-pause", "Pause or Resume Walk", action: .pause)
    nonisolated static let faster = command("walk-faster", "Walk Faster", action: .faster)
    nonisolated static let slower = command("walk-slower", "Walk Slower", action: .slower)

    enum Action: Sendable { case start, stop, pause, faster, slower }

    nonisolated private static func command(
        _ slug: String, _ name: String.LocalizationValue, action: Action
    ) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: String(localized: name), sfSymbol: "figure.walk",
            feature: .treadmillWalk, isEnabled: { NotchcastPreferences.shared.isOn(.treadmillWalk) },
            run: {
                execute(action, coordinator: NotchcastCore.treadmill) {
                    AppCore.shared.showMessage($0, tone: $1)
                }
            })
    }

    @MainActor static func execute(
        _ action: Action, coordinator: TreadmillCoordinator,
        report: (String, DialogTone) -> Void
    ) {
        do {
            guard coordinator.connected else {
                throw TreadmillFailure.unavailable
            }
            let message: String
            switch action {
            case .start:
                try coordinator.startWalk()
                let speed = coordinator.engine.requestedSpeed ?? 0
                message = String(localized: "Walk start requested at \(speed.formatted()) km/h.")
            case .stop:
                try coordinator.stopWalk()
                message = String(localized: "Walk stop requested.")
            case .pause:
                let resuming = coordinator.engine.walk?.phase == .paused
                try coordinator.togglePause()
                message = resuming ? String(localized: "Walk resume requested.")
                    : String(localized: "Walk pause requested.")
            case .faster, .slower:
                if action == .faster { try coordinator.faster() } else { try coordinator.slower() }
                let speed = coordinator.engine.requestedSpeed ?? coordinator.engine.walk?.sample.speed ?? 0
                message = String(localized: "Walk speed requested: \(speed.formatted()) km/h.")
            }
            report(message, .success)
        } catch {
            report(error.localizedDescription, .danger)
        }
    }
}

