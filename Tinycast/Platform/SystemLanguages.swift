import Foundation

/// macOS's own languages; `Locale.preferredLanguages` reads Tinycast's own language instead.
enum SystemLanguages {
    static func localized(_ key: String, bundlePath: String, languages: [String] = preferred) -> String {
        Bundle(path: bundlePath)?.localizedString(forKey: key, value: key, table: nil,
                                                  localizations: languages.map { Locale.Language(identifier: $0) }) ?? key
    }

    static var preferred: [String] {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }
}
