extension NotchcastPreferences {
    /// Volume shows only in the island, so every volume path needs both switches.
    var showsVolumeInIsland: Bool {
        isOn(.island) && isOn(.volumeLevels)
    }
}
