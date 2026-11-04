@MainActor
final class FinderToolsModule: NotchcastModule {
    private let coordinator: FinderToolsCoordinator
    private let feature: NotchcastFeature

    init(coordinator: FinderToolsCoordinator, feature: NotchcastFeature) {
        self.coordinator = coordinator
        self.feature = feature
    }

    func start() { coordinator.setEnabled(feature, true) }
    func stop() { coordinator.setEnabled(feature, false) }
}
