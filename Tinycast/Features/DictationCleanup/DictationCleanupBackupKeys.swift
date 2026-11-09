import Foundation

extension NotchcastFeature.BackupKeys {
    static let dictationCleanup = Self(allowed: [
        "notchcast.dictationCleanup.settings": .json(cleanup),
    ], excluded: [])

    private static let cleanup: NotchcastFeature.BackupValue = .object([
        "effort": .string(6, ["low", "medium", "high"]),
        "promptAddition": .string(16_384), "vocabulary": .array(500, .object([
            "spelling": .string(256), "misheardForms": .strings(50, 256),
        ])),
    ])
}
