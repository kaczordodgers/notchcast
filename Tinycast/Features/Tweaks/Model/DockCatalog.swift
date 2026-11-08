import Foundation

nonisolated enum DockCatalog {
    typealias Write = TypingPreferencePlan.Write

    static let writes: [String: [Write]] = [
        "dock-recents": [Write("com.apple.dock", "show-recents", .bool(false))],
        "dock-delay": [Write("com.apple.dock", "autohide-delay", .real(0))],
        "dock-bounce": [Write("com.apple.dock", "launchanim", .bool(false))],
        "minimize-to-app": [Write("com.apple.dock", "minimize-to-application", .bool(true))],
        "window-animations": [Write("NSAutomaticWindowAnimationsEnabled", .bool(false))],
        "tile-margins": [Write("com.apple.WindowManager", "EnableTiledWindowMargins", .bool(false))],
        "screenshot-shadow": [Write("com.apple.screencapture", "disable-shadow", .bool(true))],
        "click-to-desktop": [Write("com.apple.WindowManager", "EnableStandardClickToShowDesktop", .bool(false))],
        "desktop-widgets": [Write("com.apple.WindowManager", "StandardHideWidgets", .bool(true)),
                            Write("com.apple.WindowManager", "StageManagerHideWidgets", .bool(true))],
        "dock-autohide": [Write("com.apple.dock", "autohide", .bool(true))],
        "dock-instant": [Write("com.apple.dock", "autohide-time-modifier", .integer(0))],
        "dock-left": [Write("com.apple.dock", "orientation", .string("left"))],
        "dock-scale": [Write("com.apple.dock", "mineffect", .string("scale"))],
        "dock-corner": [Write("com.apple.dock", "wvous-br-corner", .integer(1))],
        "group-windows": [Write("com.apple.dock", "expose-group-apps", .bool(true))],
        "title-fill": [Write("AppleActionOnDoubleClick", .string("Fill"))],
        "stage-off": [Write("com.apple.WindowManager", "GloballyEnabled", .bool(false))],
        "tile-edge": [Write("com.apple.WindowManager", "EnableTilingByEdgeDrag", .bool(false))],
        "tile-top": [Write("com.apple.WindowManager", "EnableTopTilingByEdgeDrag", .bool(false))],
        "hide-desktop": [Write("com.apple.WindowManager", "HideDesktop", .bool(true)),
                         Write("com.apple.WindowManager", "StandardHideDesktopIcons", .bool(true))],
    ]
    static let preset = Set(writes.keys)

    static func restartProcess(for identifier: String) -> String? {
        if identifier == "screenshot-shadow" { return "SystemUIServer" }
        let dock: Set<String> = [
            "dock-recents", "dock-delay", "dock-bounce", "minimize-to-app", "dock-autohide",
            "dock-instant", "dock-left", "dock-scale", "dock-corner", "group-windows",
        ]
        return dock.contains(identifier) ? "Dock" : nil
    }
}
