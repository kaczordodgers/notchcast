import AppKit

extension TreadmillCoordinator {
    nonisolated static let stopCommand = NotchcastCommand(
        slug: "treadmill-stop", name: String(localized: "Treadmill: Stop"), sfSymbol: "stop.fill",
        isEnabled: { NotchcastPreferences.shared.isOn(.treadmillWalk) },
        run: { NotchcastCore.treadmill.runCommand(start: false) })

    nonisolated static let startCommand = NotchcastCommand(
        slug: "treadmill-start-walk", name: String(localized: "Treadmill: Start Walk"), sfSymbol: "figure.walk",
        isEnabled: { NotchcastPreferences.shared.isOn(.treadmillWalk) },
        run: { NotchcastCore.treadmill.runCommand(start: true) })

    @discardableResult
    func runCommand(start: Bool,
                    enabled: @escaping () -> Bool = { NotchcastPreferences.shared.isOn(.treadmillWalk) },
                    confirm: @escaping @MainActor () async -> Bool = confirmStart,
                    message: @escaping (String, DialogTone) -> Void = {
                        AppCore.shared.showMessage($0, tone: $1)
                    }) -> Task<Void, Never>? {
        guard enabled() else { return nil }
        return Task {
            if start, !(await confirm()) { return }
            guard !Task.isCancelled, enabled() else { return }
            do {
                if start { try startWalk() } else { try stopWalk() }
                message(String(localized: "Treadmill command sent."), .success)
            } catch {
                message(error.localizedDescription, .danger)
            }
        }
    }

    private static func confirmStart() async -> Bool {
        await AppCore.shared.confirm(
            title: String(localized: "Start walking at 4 km/h?"), message: nil,
            symbol: "figure.walk", confirmTitle: String(localized: "Start Walk"),
            tone: .neutral, confirmRole: .default)
    }
}
