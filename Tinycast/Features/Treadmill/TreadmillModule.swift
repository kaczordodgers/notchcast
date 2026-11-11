import Foundation

@MainActor
final class TreadmillModule: NotchcastModule {
    private let coordinator: TreadmillCoordinator
    let capability: TreadmillCoordinator.Capability

    init(_ coordinator: TreadmillCoordinator, capability: TreadmillCoordinator.Capability) {
        self.coordinator = coordinator
        self.capability = capability
    }

    func start() { coordinator.setEnabled(capability, true) }
    func stop() { coordinator.setEnabled(capability, false) }
}

extension TreadmillCoordinator {
    static func live(bundleID: String = Bundle.main.bundleIdentifier ?? "app.notchcast.dev") -> TreadmillCoordinator {
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        let repository = TreadmillRepository(
            directory: support.appending(path: bundleID).appending(path: "notchcast/treadmill"))
        let defaults = UserDefaults(suiteName: bundleID + ".notchcast")!
        return TreadmillCoordinator(transport: BluetoothTreadmillTransport(),
                                    history: TreadmillHistoryStore(repository: repository),
                                    preferences: TreadmillPreferences(defaults: defaults),
                                    reminders: TreadmillReminders(enabled: {
                                        NotchcastPreferences.shared.isOn(.treadmillHistory)
                                            && NotchcastPreferences.shared.isEnabled(.islandStatusMessages)
                                    }, present: {
                                        IslandActivityCenter.shared.showMessage($0, tone: .neutral, dwell: 8,
                                                                                id: $1, symbol: "figure.walk")
                                    }))
    }
}
