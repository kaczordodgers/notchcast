import Foundation

nonisolated enum TypingCatalog {
    typealias Write = TypingPreferencePlan.Write

    static let writes: [String: [Write]] = [
        "autocorrect": [Write("NSAutomaticSpellingCorrectionEnabled", .bool(false))],
        "smart-punctuation": [Write("NSAutomaticQuoteSubstitutionEnabled", .bool(false)),
                              Write("NSAutomaticDashSubstitutionEnabled", .bool(false))],
        "double-space-period": [Write("NSAutomaticPeriodSubstitutionEnabled", .bool(false))],
        "auto-capitalize": [Write("NSAutomaticCapitalizationEnabled", .bool(false))],
        "key-repeat": [Write("ApplePressAndHoldEnabled", .bool(false))],
        "repeat-rate": [Write("KeyRepeat", .integer(2))],
        "repeat-delay": [Write("InitialKeyRepeat", .integer(15))],
    ]
    static let preset: Set<String> = ["smart-punctuation", "double-space-period", "repeat-rate", "repeat-delay"]
}
