import Foundation

extension NotchcastFeature.BackupKeys {
    static let appearance = Self(allowed: [
        AppearanceSurfaceStyle.defaultsKey: .string(5, ["glass", "black", "matte"]),
        AppearanceStore.opacityKey: .number(0.2...1),
        AppearanceStore.lightKey: .json(.optional(theme)),
        AppearanceStore.darkKey: .json(.optional(theme)),
        AppearanceStore.importedKey: .json(.array(100, theme)),
    ], excluded: [], snapshot: {
        // Reads defaults: building an AppearanceStore here would refresh the app's colours.
        let defaults = AppearanceStore.preferences
        let saved: [String: Any?] = [
            AppearanceSurfaceStyle.defaultsKey: defaults.string(forKey: AppearanceSurfaceStyle.defaultsKey) ?? "glass",
            AppearanceStore.opacityKey: defaults.object(forKey: AppearanceStore.opacityKey) ?? AppearanceStore.defaultOpacity,
            AppearanceStore.lightKey: json(defaults.object(forKey: AppearanceStore.lightKey), missing: "null"),
            AppearanceStore.darkKey: json(defaults.object(forKey: AppearanceStore.darkKey), missing: "null"),
            AppearanceStore.importedKey: json(defaults.object(forKey: AppearanceStore.importedKey), missing: "[]"),
        ]
        return saved.compactMapValues { $0 }
    }, validate: { values in
        try check(values[AppearanceStore.lightKey], fits: .light)
        try check(values[AppearanceStore.darkKey], fits: .dark)
        if let value = values[AppearanceStore.importedKey] as? String { _ = try decode([RaycastTheme].self, value) }
    }, apply: { values in
        let store = AppearanceStore.current ?? AppearanceStore()
        if let value = values[AppearanceSurfaceStyle.defaultsKey] as? String,
           let style = AppearanceSurfaceStyle(rawValue: value) { store.surfaceStyle = style }
        if let value = values[AppearanceStore.opacityKey] as? Double { store.backgroundOpacity = value }
        if let value = values[AppearanceStore.importedKey] as? String {
            try store.replaceImported(decode([RaycastTheme].self, value))
        }
        if let value = values[AppearanceStore.lightKey] as? String {
            try store.select(decode(RaycastTheme?.self, value), for: .light)
        }
        if let value = values[AppearanceStore.darkKey] as? String {
            try store.select(decode(RaycastTheme?.self, value), for: .dark)
        }
    })

    private static let theme: NotchcastFeature.BackupValue = .object([
        "name": .string(256), "author": .string(256), "appearance": .string(5, ["light", "dark"]),
        "colors": .colors,
    ])

    /// Nil for a stored value that is not UTF-8 JSON, so the snapshot leaves out that key alone.
    private static func json(_ stored: Any?, missing: String) -> String? {
        guard let stored else { return missing }
        return (stored as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func check(_ value: Any?, fits slot: RaycastTheme.Appearance) throws {
        if let value = value as? String, let selected = try decode(RaycastTheme?.self, value), selected.appearance != slot {
            throw RaycastTheme.ValidationError.wrongAppearance
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ value: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }
}
