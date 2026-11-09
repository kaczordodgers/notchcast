import Foundation

@main
struct TweakCompletionTests {
    static func main() throws {
        let home = URL(fileURLWithPath: "/example")
        let entries = MacSetupPresetCatalog.entries(home: home)
        precondition(Set(entries.map(\.id)).count == entries.count)
        let selected = MacSetupPresetCatalog.selection(.full, home: home)
        precondition(!selected.contains { $0.id == "autocorrect" || $0.id == "key-repeat" })
        precondition(selected.contains { $0.id == "tinting" })
        for group in AIOffDaemonPlan.Group.allCases {
            let disable = AIOffDaemonPlan.commands(group, uid: 501)
            let enable = AIOffDaemonPlan.commands(group, uid: 501, restoring: true)
            precondition(disable.count == enable.count && !disable.isEmpty)
            precondition(disable.allSatisfy { $0.arguments[0] == "disable" })
            precondition(enable.allSatisfy { $0.arguments[0] == "enable" })
            precondition(zip(disable, enable).allSatisfy { $0.arguments[1] == $1.arguments[1] })
        }
        let service = AIOffNativeModelService()
        let plan = try service.removalPlan(keeping: ["genmoji"],
                                          blockedAssets: Set(AIOffCatalog.assetTypes.values))
        precondition(!plan.models.contains(AIOffCatalog.foundation))
        precondition(!plan.models.contains(AIOffCatalog.visual))
        var calls = 0
        try service.remove(plan) { request in
            calls += 1
            precondition(request.configuration["Operation"] as? String == "ResetAssetSets")
        }
        precondition(calls == 1)
        enum Injected: Error { case failed }
        do {
            try service.remove(plan) { _ in throw Injected.failed }
            fatalError("Runner failure must propagate")
        } catch Injected.failed { }
        print("PASS: unique preset rows, Spaces ownership, selections, reversible daemon plans and injected model removal")
    }
}
