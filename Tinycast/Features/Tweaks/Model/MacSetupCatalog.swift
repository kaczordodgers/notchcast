import Foundation

nonisolated enum MacSetupCatalog {
    static let preferences: [(TweakPreference, TweakValue)] = [
        AIOffCatalog.pref("com.apple.dock", "orientation", .string("left")),
        AIOffCatalog.pref("com.apple.dock", "autohide", .bool(true)),
        AIOffCatalog.pref("com.apple.dock", "autohide-delay", .real(0)),
        AIOffCatalog.pref("com.apple.dock", "autohide-time-modifier", .integer(0)),
        AIOffCatalog.pref("com.apple.dock", "mineffect", .string("scale")),
        AIOffCatalog.pref(".GlobalPreferences", "AppleInterfaceStyle", .string("Dark")),
        AIOffCatalog.pref("com.apple.menuextra.clock", "ShowSeconds", .bool(true)),
        AIOffCatalog.pref(".GlobalPreferences", "KeyRepeat", .integer(2)),
        AIOffCatalog.pref(".GlobalPreferences", "InitialKeyRepeat", .integer(15)),
        AIOffCatalog.pref(".GlobalPreferences", "com.apple.swipescrolldirection", .bool(false)),
        AIOffCatalog.pref(".GlobalPreferences", "com.apple.trackpad.scaling", .integer(2)),
        AIOffCatalog.pref(".GlobalPreferences", "AppleReduceDesktopTinting", .bool(false)),
        AIOffCatalog.pref("com.apple.screencapture", "disable-shadow", .bool(true))
    ] + ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].flatMap {
        [AIOffCatalog.pref($0, "Clicking", .bool(true)),
         AIOffCatalog.pref($0, "FirstClickThreshold", .integer(1))]
    }
}
