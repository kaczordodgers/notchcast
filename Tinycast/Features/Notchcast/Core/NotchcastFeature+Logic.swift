// Not merge=union: logic over several lines must conflict for real, never be appended twice.
extension NotchcastFeature {
    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool { !isSystemFeature && needsIslandArm }

    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool { !isSystemFeature && !isLauncherKeysFeature && defaultEnabledArm }

    var isSystemFeature: Bool { settingsGroup == .systemTools }
}
