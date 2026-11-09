import Foundation

@main
struct TweakCoreTests {
    static func main() throws {
        let preference = TweakPreference(domain: "example.test", key: "value")
        let plan = try MacSetupPlan(desired: [(preference, .bool(false))], readings: [preference: .absent])
        precondition(plan.changes.count == 1)
        let undo = try plan.undo(readings: [preference: .bool(false)])
        precondition(undo.changes.first?.after == .absent)
        precondition(TweakCommand.preference(preference, value: .absent).arguments
                     == ["delete", "example.test", "value"])
        let hostile = TweakPreference(domain: "test", key: "$(echo nope)")
        precondition(TweakCommand.preference(hostile, value: .string("' ; exit")).arguments
                     == ["write", "test", "$(echo nope)", "-string", "' ; exit"])
        do {
            _ = try plan.undo(readings: [preference: .bool(true)])
            fatalError("Undo must preserve external edits")
        } catch MacSetupPlan.Failure.drift { }
        do {
            _ = try MacSetupPlan(desired: [(preference, .bool(false))], readings: [:])
            fatalError("Unreadable is not absent")
        } catch MacSetupPlan.Failure.missingReading { }
        var writes = 0
        let receipt = TweakPlanRunner().apply(plan) { _, _ in writes += 1 }
        precondition(writes == 1 && receipt.failure == nil && receipt.completed.count == 1)
        enum InjectedFailure: Error { case failed }
        let failure = TweakPlanRunner().apply(plan) { _, _ in throw InjectedFailure.failed }
        precondition(failure.completed.isEmpty && failure.failure != nil)
        precondition(AIOffCatalog.features.count == 14)
        let service = AIOffModelService()
        let sizes = try service.read { _ in 0 }
        precondition(sizes.count == 5)
        do {
            _ = try service.removalPlan(keeping: [], blockedAssets: [])
            fatalError("Do not remove models before blocking downloads")
        } catch AIOffModelService.Failure.downloadsNotBlocked { }
        let removal = try service.removalPlan(keeping: [], blockedAssets: Set(AIOffCatalog.assetTypes.values))
        precondition(removal.count == 5)
        precondition(AIOffCatalog.removableModels(keeping: []).count == 5)
        precondition(!AIOffCatalog.removableModels(keeping: ["genmoji"]).contains(AIOffCatalog.foundation))
        precondition(!AIOffCatalog.removableModels(keeping: ["genmoji"]).contains(AIOffCatalog.visual))
        let data = try TweakProfile.data(bundleIdentifier: "test.channel", keepingAI: [], privacy: ["analytics"])
        let profile = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        precondition(profile?["PayloadScope"] as? String == "System")
        precondition(UUID(uuidString: profile?["PayloadUUID"] as? String ?? "") != nil)
        let again = try TweakProfile.data(bundleIdentifier: "test.channel", keepingAI: [], privacy: ["analytics"])
        let second = try PropertyListSerialization.propertyList(from: again, format: nil) as? NSDictionary
        precondition((profile as NSDictionary?) == second)
        precondition(SpotlightIndexing.parse("/:\n Indexing disabled.\n").isOff)
        precondition(!SpotlightIndexing.parse("/:\n Error: unknown indexing state.\n").isOff)
        precondition(!SpotlightIndexing.parse("").isOff)
        precondition(SpotlightIndexing.parse("/:\n Indexing enabled.\n").needsTurnOff(featureEnabled: true))
        precondition(!SpotlightIndexing.parse("/:\n Indexing enabled.\n").needsTurnOff(featureEnabled: false))
        print("PASS: tweaks plans, Undo, injected failures, profiles, shared models and Spotlight")
    }
}
