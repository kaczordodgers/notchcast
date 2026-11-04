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

    func runCommand(start: Bool, enabled: () -> Bool = { NotchcastPreferences.shared.isOn(.treadmillWalk) },
                    confirm: @MainActor () -> Bool = confirmStart,
                    message: (String) -> Void = { AppCore.shared.showMessage($0) }) {
        guard enabled() else { return }
        guard !start || confirm() else { return }
        guard enabled() else { return }
        do {
            if start { try startWalk() } else { try stopWalk() }
            message(String(localized: "Treadmill command sent."))
        } catch {
            message(error.localizedDescription)
        }
    }

    private static func confirmStart() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Start walking at 4 km/h?")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Start Walk"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}
