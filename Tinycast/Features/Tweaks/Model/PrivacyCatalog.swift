import Foundation

nonisolated enum PrivacyCatalog {
    static let restrictions = ["analytics": "allowDiagnosticSubmission",
                               "personalized-ads": "allowApplePersonalizedAdvertising",
                               "spotlight-web": "allowSpotlightInternetResults"]
    static let preferences: [String: [(TweakPreference, TweakValue)]] = [
        "improve-siri": [AIOffCatalog.pref("com.apple.assistant.support", "Siri Data Sharing Opt-In Status", .integer(2))],
        "improve-search": [AIOffCatalog.pref("com.apple.assistant.support", "Search Queries Data Sharing Status", .integer(2))],
        "lookup-suggestions": [AIOffCatalog.pref("com.apple.lookup.shared", "LookupSuggestionsDisabled", .bool(true))],
        "safari-suggestions": [AIOffCatalog.pref("com.apple.Safari", "UniversalSearchEnabled", .bool(false)),
                               AIOffCatalog.pref("com.apple.Safari", "SuppressSearchSuggestions", .bool(true))]
    ]
}
