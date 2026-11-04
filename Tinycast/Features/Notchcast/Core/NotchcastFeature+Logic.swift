extension NotchcastFeature {
    var isWired: Bool {
        !Self.unwired.contains(self)
    }

    /// Switches kept out of Settings until a user can reach them; the code stays.
    /// Each reason is in notchcast/switch-path-allowlist-*.json. Unhide = delete its line.
    static let unwired: Set<Self> = [
        .githubSearch,
        .aiUsage,
        .aiUsageOtherMac,
        .inUseMarks,
        .dayWeather,
        .dayMarkets,
        .treadmillHistory,
        .agentSessions,
        .agentPricing,
        .captureTrimmer,
        .recording,
        .backupRunNow,
        .backupBrowseRestore,
        .markdownFiles,
        .plainTextFiles,
        .buildStats,
        .killProcess,
        .launcherAnswers,
        .treadmillWalk,
        .katana,
        .agentAnswer,
        .voiceAsk,
        .cleanSystem,
        .remoteScreen,
        .machMBPFans,
        .macSetup,
        .agentConfirmation,
        .machineSetupProfile,
    ]

    static var systemToolsSettingsFeatures: [Self] {
        [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess,
         .macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices].filter(\.isWired)
    }

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
