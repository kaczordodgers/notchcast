import Foundation

nonisolated enum AIOffCatalog {
    struct Feature: Sendable {
        let id: String
        let restrictions: [String]
        var preferences: [(TweakPreference, TweakValue)] = []
        var models: Set<String> = []
    }

    static let foundation = "com.apple.modelcatalog"
    static let visual = "com.apple.MobileAsset.UAF.FM.Visual"
    static let spatial = "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"
    static let cleanup = "com.apple.MobileAsset.UAF.Photos.MagicCleanup"
    static let code = "com.apple.MobileAsset.UAF.FM.CodeLM"
    static let assetTypes = [foundation: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
                             visual: visual, spatial: spatial, cleanup: cleanup, code: code]

    static let features: [Feature] = [
        .init(id: "siri", restrictions: ["allowAssistant"], preferences: [
            pref("com.apple.assistant.support", "Assistant Enabled", .bool(false)),
            pref("com.apple.Siri", "StatusMenuVisible", .bool(false)),
            pref("com.apple.Siri", "VoiceTriggerUserEnabled", .bool(false))], models: [foundation]),
        .init(id: "chatgpt", restrictions: ["allowExternalIntelligenceIntegrations",
                                          "allowExternalIntelligenceIntegrationsSignIn"]),
        .init(id: "writing-tools", restrictions: ["allowWritingTools"], models: [foundation]),
        .init(id: "genmoji", restrictions: ["allowGenmoji"], models: [foundation, visual]),
        .init(id: "image-playground", restrictions: ["allowImagePlayground"], models: [foundation, visual]),
        .init(id: "mail", restrictions: ["allowMailSummary", "allowMailSmartReplies"], preferences: [
            pref("group.com.apple.mail", "DisableAutomaticMessageSummarization", .bool(true)),
            pref("group.com.apple.mail", "PersonalizedSmartReplies", .bool(false))], models: [foundation]),
        .init(id: "notification-summaries", restrictions: [], preferences: [
            pref("group.com.apple.usernoted", "summarize_previews", .bool(false))], models: [foundation]),
        .init(id: "messages-summaries", restrictions: [], preferences: [
            pref("com.apple.MobileSMS", "messageSummarizationEnabled", .bool(false))], models: [foundation]),
        .init(id: "safari-summaries", restrictions: ["allowSafariSummary"], models: [foundation]),
        .init(id: "notes-summaries", restrictions: ["allowNotesTranscriptionSummary"], models: [foundation]),
        .init(id: "inline-predictions", restrictions: [], preferences: [
            pref(".GlobalPreferences", "NSAutomaticInlinePredictionEnabled", .bool(false))]),
        .init(id: "spatial-photos", restrictions: [], preferences: [
            pref("com.apple.spatialphotosrelive", "LocallyDisabled", .bool(true))], models: [spatial]),
        .init(id: "photos-clean-up", restrictions: [], models: [cleanup]),
        .init(id: "xcode-completion", restrictions: [], models: [code])
    ]

    static func pref(_ domain: String, _ key: String, _ value: TweakValue) -> (TweakPreference, TweakValue) {
        (.init(domain: domain, key: key), value)
    }

    static func removableModels(keeping kept: Set<String>) -> [String] {
        let required = features.filter { kept.contains($0.id) }.reduce(into: Set<String>()) { $0.formUnion($1.models) }
        return assetTypes.keys.filter { !required.contains($0) }.sorted()
    }
}
