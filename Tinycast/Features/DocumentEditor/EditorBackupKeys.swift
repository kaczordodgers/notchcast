import Foundation

extension NotchcastFeature.BackupKeys {
    static let editor = Self(allowed: [
        fontKey: .string(13, ["system", "jetBrainsMono"]),
        themeKey: .string(10, ["system", "githubDark"]),
        pairsKey: .bool,
    ], excluded: [], snapshot: {
        let editor = EditorCoordinator.shared.editorPreferences
        return [fontKey: editor.font.rawValue, themeKey: editor.theme.rawValue, pairsKey: editor.pairsAutomatically]
    }, apply: { values in
        let editor = EditorCoordinator.shared.editorPreferences
        if let value = values[fontKey] as? String, let font = EditorPreferences.FontPreset(rawValue: value) { editor.font = font }
        if let value = values[themeKey] as? String, let theme = EditorPreferences.ThemePreset(rawValue: value) {
            editor.theme = theme
        }
        if let value = values[pairsKey] as? Bool { editor.pairsAutomatically = value }
    })

    /// Only a backup uses these names; the editor keeps bare keys in a defaults suite of its own.
    private static let fontKey = "notchcast.editor.font"
    private static let themeKey = "notchcast.editor.theme"
    private static let pairsKey = "notchcast.editor.pairsAutomatically"
}
