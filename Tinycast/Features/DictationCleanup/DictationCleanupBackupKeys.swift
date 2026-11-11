import Foundation

extension NotchcastFeature.BackupKeys {
    static let dictationCleanup = Self(allowed: [
        cleanupKey: .json(cleanup),
    ], excluded: [], snapshot: {
        let settings = try store.read()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = Cleanup(effort: settings.effort, promptAddition: settings.promptAddition,
                            vocabulary: settings.vocabulary)
        return [cleanupKey: String(decoding: try encoder.encode(saved), as: UTF8.self)]
    }, validate: { values in
        if let value = values[cleanupKey] as? String { _ = try decoded(value) }
    }, apply: { values in
        guard let value = values[cleanupKey] as? String else { return }
        let restored = try decoded(value)
        var current = try store.read()
        current.effort = restored.effort
        current.promptAddition = restored.promptAddition
        current.vocabulary = restored.vocabulary
        try store.save(current)
        DictationCleanupModule.shared.load()
    })

    /// Only a backup names the settings this way; the store keeps them under its own defaults key.
    private static let cleanupKey = "notchcast.dictationCleanup.settings"

    private static let cleanup: NotchcastFeature.BackupValue = .object([
        "effort": .string(6, ["low", "medium", "high"]),
        "promptAddition": .string(16_384), "vocabulary": .array(500, .object([
            "spelling": .string(256), "misheardForms": .strings(50, 256),
        ])),
    ])

    /// The fields a backup carries: the switch, endpoint and key stay on this Mac.
    private struct Cleanup: Codable {
        var effort: DictationCleanupSettings.Effort
        var promptAddition: String
        var vocabulary: [DictationCleanupSettings.VocabularyTerm]
    }

    private static var store: DictationCleanupSettingsStore {
        let identity = NotchcastIdentity.current
        return DictationCleanupSettingsStore(defaults: identity.defaults, bundleIdentifier: identity.bundleID)
    }

    private static func decoded(_ value: String) throws -> Cleanup {
        try JSONDecoder().decode(Cleanup.self, from: Data(value.utf8))
    }
}
