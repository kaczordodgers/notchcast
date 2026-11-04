import Foundation

@MainActor
struct ForkSettingsBackupState {
    let snapshot: () throws -> [String: Any]
    let validate: ([String: Any]) throws -> Void
    let apply: ([String: Any]) throws -> Void

    static func quitValues(_ store: QuitProtectionStore) -> [String: Any] {
        ["notchcast.quitProtection.quitEnabled": store.configuration.quitEnabled,
         "notchcast.quitProtection.closeEnabled": store.configuration.closeEnabled,
         "notchcast.quitProtection.mode": store.configuration.mode.rawValue,
         "notchcast.quitProtection.exceptions": store.configuration.exceptions.sorted()]
    }

    static func applyQuit(_ values: [String: Any], to store: QuitProtectionStore) {
        guard values.keys.contains(where: { $0.hasPrefix("notchcast.quitProtection.") }) else { return }
        var configuration = store.configuration
        if let value = values["notchcast.quitProtection.quitEnabled"] as? Bool { configuration.quitEnabled = value }
        if let value = values["notchcast.quitProtection.closeEnabled"] as? Bool { configuration.closeEnabled = value }
        if let value = values["notchcast.quitProtection.mode"] as? String,
           let mode = QuitProtectionEngine.Mode(rawValue: value) { configuration.mode = mode }
        if let value = values["notchcast.quitProtection.exceptions"] as? [String] { configuration.exceptions = Set(value) }
        store.configuration = configuration
    }
}
