import Foundation
import OSLog

extension ForkSettingsBackupState {
    static var live: Self {
        Self(snapshot: {
            var values = ForkSettingsBackupRestore.snapshot(.shared)
            for feature in NotchcastBackupState.all { values.merge(feature.snapshot()) { _, value in value } }
            let editor = EditorCoordinator.shared.editorPreferences
            values["notchcast.editor.font"] = editor.font.rawValue
            values["notchcast.editor.theme"] = editor.theme.rawValue
            values["notchcast.editor.pairsAutomatically"] = editor.pairsAutomatically
            values["notchcast.day.marketSymbols"] = DayMarketsModule.shared.store.symbols
            capture("notchcast.day.weatherPlace", into: &values) { try json(DayWeatherModule.shared.store.place) }
            let defaults = AppearanceStore.preferences
            values["notchcast.colorPicker.format"] = defaults.string(forKey: "notchcast.colorPicker.format") ?? "hex"
            values["notchcast.appearance.surface"] = defaults.string(forKey: AppearanceSurfaceStyle.defaultsKey) ?? "glass"
            values["notchcast.appearance.theme.backgroundOpacity"] =
                defaults.object(forKey: AppearanceStore.opacityKey) ?? AppearanceStore.defaultOpacity
            for (key, fallback) in [(AppearanceStore.lightKey, "null"), (AppearanceStore.darkKey, "null"),
                                    (AppearanceStore.importedKey, "[]")] {
                capture(key, into: &values) {
                    guard let raw = defaults.object(forKey: key) else { return fallback }
                    guard let data = raw as? Data, let string = String(data: data, encoding: .utf8) else {
                        throw ForkSettingsBackupEngine.Failure.invalidArchive
                    }
                    return string
                }
            }
            capture("notchcast.dictationCleanup.settings", into: &values) {
                let cleanup = try cleanupStore.read()
                return try json(Cleanup(effort: cleanup.effort,
                    promptAddition: cleanup.promptAddition, vocabulary: cleanup.vocabulary))
            }
            for key in Array(values.keys) {
                do { try validateLive([key: values[key]!]) }
                catch { values.removeValue(forKey: key); logSkipped(key) }
            }
            return values
        }, validate: validateLive, apply: { values in
            try validateLive(values)
            for feature in NotchcastBackupState.all { feature.apply(values) }
            let editor = EditorCoordinator.shared.editorPreferences
            if let value = values["notchcast.editor.font"] as? String,
               let font = EditorPreferences.FontPreset(rawValue: value) { editor.font = font }
            if let value = values["notchcast.editor.theme"] as? String,
               let theme = EditorPreferences.ThemePreset(rawValue: value) { editor.theme = theme }
            if let value = values["notchcast.editor.pairsAutomatically"] as? Bool { editor.pairsAutomatically = value }
            if let value = values["notchcast.day.marketSymbols"] as? [String] { DayMarketsModule.shared.store.setSymbols(value) }
            if let value = values["notchcast.day.weatherPlace"] as? String {
                DayWeatherModule.shared.store.select(try decode(DayWeatherPlace?.self, value))
            }
            if let value = values["notchcast.colorPicker.format"] as? String {
                AppearanceStore.preferences.set(value, forKey: "notchcast.colorPicker.format")
                if let format = ColorPickerFormat(rawValue: value) { ColorPickerModule.shared.format = format }
            }
            let appearance = AppearanceStore.current ?? AppearanceStore()
            if let value = values["notchcast.appearance.surface"] as? String,
               let style = AppearanceSurfaceStyle(rawValue: value) { appearance.surfaceStyle = style }
            if let value = values["notchcast.appearance.theme.backgroundOpacity"] as? Double {
                appearance.backgroundOpacity = value
            }
            if let value = values["notchcast.appearance.themes.imported"] as? String {
                try appearance.replaceImported(decode([RaycastTheme].self, value))
            }
            if let value = values["notchcast.appearance.theme.light"] as? String {
                try appearance.select(decode(RaycastTheme?.self, value), for: .light)
            }
            if let value = values["notchcast.appearance.theme.dark"] as? String {
                try appearance.select(decode(RaycastTheme?.self, value), for: .dark)
            }
            if let value = values["notchcast.dictationCleanup.settings"] as? String {
                let restored = try decode(Cleanup.self, value)
                var current = try cleanupStore.read()
                current.effort = restored.effort
                current.promptAddition = restored.promptAddition
                current.vocabulary = restored.vocabulary
                try cleanupStore.save(current)
                DictationCleanupModule.shared.load()
            }
            try ForkSettingsBackupRestore.apply(values, to: .shared)
        })
    }

    private static var cleanupStore: DictationCleanupSettingsStore {
        let identifier = NotchcastIdentity.current.bundleID
        return DictationCleanupSettingsStore(defaults: DayStorage.defaults, bundleIdentifier: identifier)
    }

    private struct Cleanup: Codable {
        var effort: DictationCleanupSettings.Effort
        var promptAddition: String
        var vocabulary: [DictationCleanupSettings.VocabularyTerm]
    }

    private static func capture(_ key: String, into values: inout [String: Any], read: () throws -> String) {
        do { values[key] = try read() }
        catch { logSkipped(key) }
    }

    private static func logSkipped(_ key: String) {
        Logger(subsystem: NotchcastIdentity.current.bundleID, category: "SettingsBackup")
            .error("Skipping invalid backup key: \(key, privacy: .public)")
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let string = String(bytes: try encoder.encode(value), encoding: .utf8) else {
            throw ForkSettingsBackupEngine.Failure.invalidArchive
        }
        return string
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ value: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }

    private static func validateLive(_ values: [String: Any]) throws {
        try ForkSettingsBackupEngine.validate(values)
        for (key, appearance) in [("notchcast.appearance.theme.light", RaycastTheme.Appearance.light),
                                  ("notchcast.appearance.theme.dark", .dark)] {
            if let value = values[key] as? String, let theme = try decode(RaycastTheme?.self, value),
               theme.appearance != appearance { throw ForkSettingsBackupEngine.Failure.invalidArchive }
        }
        if let value = values["notchcast.appearance.themes.imported"] as? String { _ = try decode([RaycastTheme].self, value) }
        if let value = values["notchcast.day.weatherPlace"] as? String { _ = try decode(DayWeatherPlace?.self, value) }
        if let value = values["notchcast.dictationCleanup.settings"] as? String { _ = try decode(Cleanup.self, value) }
    }
}
