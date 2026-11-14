import Foundation

extension SystemLanguages {
    static func localized(_ key: String, bundlePath: String, languages: [String] = preferred) -> String {
        Bundle(path: bundlePath)?.localizedString(forKey: key, value: key, table: nil,
                                                  localizations: languages.map { Locale.Language(identifier: $0) }) ?? key
    }
}
