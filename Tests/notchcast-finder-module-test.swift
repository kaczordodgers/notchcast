// notchcast-sources: Tinycast/Features/FinderTools/FinderToolsModule.swift
@MainActor
protocol NotchcastModule {
    func start()
    func stop()
}

enum NotchcastFeature: Hashable { case finderCutPaste, finderRename }

@MainActor
final class FinderToolsCoordinator {
    var enabled: Set<NotchcastFeature> = []
    var actions = 0

    func setEnabled(_ feature: NotchcastFeature, _ value: Bool) {
        if value { enabled.insert(feature) } else { enabled.remove(feature) }
    }

    func cut() {
        if enabled.contains(.finderCutPaste) { actions += 1 }
    }
}

@main @MainActor
struct FinderModuleTests {
    static func main() {
        let coordinator = FinderToolsCoordinator()
        let cut = FinderToolsModule(coordinator: coordinator, feature: .finderCutPaste)
        let rename = FinderToolsModule(coordinator: coordinator, feature: .finderRename)
        cut.start()
        rename.start()
        coordinator.cut()
        precondition(coordinator.actions == 1)
        cut.stop()
        coordinator.cut()
        precondition(coordinator.actions == 1)
        precondition(coordinator.enabled == [.finderRename])
        rename.stop()
        precondition(coordinator.enabled.isEmpty)
        print("PASS: Finder modules independently forward lifecycle to their coordinator")
    }
}
