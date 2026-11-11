// notchcast-kit: core
import Foundation

@MainActor
final class GateModule: NotchcastModule {
    var isRunning = false
    func start() { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@main
@MainActor
struct LinkHealthGateTests {
    static func main() async {
        let suite = "link-health-gate-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let leaves: [NotchcastFeature] = [.linkHealth, .shelfBetweenMacs, .remoteScreen, .machMBPFans, .machBlockedDialogAlert]
        for feature in leaves {
            precondition(feature.dependencies.contains(.machLink), "\(feature) must declare Machine Link")
        }
        precondition(NotchcastFeature.sendFiles.dependencies == [.machRemote])
        precondition(NotchcastFeature.updateRemote.dependencies == [.machRemote])
        precondition(NotchcastFeature.agentCLI.dependencies == [.agentActions])
        precondition(NotchcastFeature.eventReminder.dependencies == [.island, .islandLiveActivities])
        for feature in NotchcastFeature.allCases {
            let entry = NotchcastModuleController.Entry(requires: [feature], module: GateModule()).gatedOnDependencies
            precondition(Set(feature.dependencies + [feature]).isSubset(of: entry.requires), "\(feature) starts without a dependency")
        }

        let module = GateModule()
        let controller = NotchcastModuleController(
            [NotchcastModuleController.Entry(requires: [.linkHealth], module: module).gatedOnDependencies],
            preferences: preferences)
        controller.run()
        preferences.set(.machLink, false)
        preferences.set(.linkHealth, true)
        await settle()
        precondition(preferences.isOn(.linkHealth) && !preferences.isEnabled(.linkHealth), "Link Health stays on without Machine Link")
        precondition(!module.isRunning)
        preferences.set(.machLink, true)
        await settle()
        precondition(preferences.isEnabled(.linkHealth) && module.isRunning)
        preferences.set(.machLink, false)
        await settle()
        precondition(!preferences.isEnabled(.linkHealth) && !module.isRunning, "Link Health outlives Machine Link")
        print("PASS: Link Health commands, settings and module go off with Machine Link; every entry gates on its dependencies")
    }
}
