import Foundation

extension NotchcastFeature.BackupKeys {
    static let appearance = Self(allowed: [
        "notchcast.appearance.surface": .string(5, ["glass", "black", "matte"]),
        "notchcast.appearance.theme.backgroundOpacity": .number(0.2...1),
        "notchcast.appearance.theme.light": .json(.optional(theme)),
        "notchcast.appearance.theme.dark": .json(.optional(theme)),
        "notchcast.appearance.themes.imported": .json(.array(100, theme)),
    ], excluded: [])

    private static let theme: NotchcastFeature.BackupValue = .object([
        "name": .string(256), "author": .string(256), "appearance": .string(5, ["light", "dark"]),
        "colors": .colors,
    ])
}
