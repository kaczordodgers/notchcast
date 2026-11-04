// Not merge=union: logic over several lines must conflict for real, never be appended twice.
extension NotchcastFeature {
    var isWired: Bool {
        ![Self.killProcess, .macSetup, .aiFeaturesOff, .privacyChoices].contains(self)
    }

    static var systemToolsSettingsFeatures: [Self] {
        [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess,
         .macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices].filter(\.isWired)
    }

    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        !isSystemFeature && !isSystemTweak && settingsGroup != .clean && needsIslandArm
    }

    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool {
        !isSystemFeature && !isSystemTweak && settingsGroup != .clean && !isLauncherKeysFeature && defaultEnabledArm
    }

    var isSystemFeature: Bool {
        self == .katana || settingsGroup == .systemTools || settingsGroup == .tools
    }
}
