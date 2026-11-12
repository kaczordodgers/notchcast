import Foundation

@main
struct TweakCoreTests {
    static func main() throws {
        precondition(AIOffCatalog.features.count == 14)
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
        print("PASS: tweaks profiles and shared models")
    }
}
// notchcast-sources: Tinycast/Features/Tweaks/Model/*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
