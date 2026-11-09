import Foundation

extension NotchcastFeature {
    /// What the hub states about one feature, declared once in the folder that holds its code.
    struct Descriptor: Sendable {
        let title: String
        let subtitle: String
        let group: SettingsGroup
        let defaultEnabled: Bool
        /// Listing `.island` is what makes a feature island-only; `needsIsland` reads it from here.
        let dependencies: [NotchcastFeature]
        let requiredGrants: [NotchcastGrant]
        let isSystemFeature: Bool
        let isSystemTweak: Bool
    }

    /// One line per described feature; the others still answer from NotchcastFeature's switches.
    static let descriptors: [Self: Descriptor] = [
        .hideCommandM: .hideCommandM,
        .lowDiskWarning: .lowDiskWarning,
        .linkHealth: .linkHealth,
        .eventReminder: .eventReminder,
        .linkQuickFixes: .linkQuickFixes,
        .tasks: .tasks,
        .tasksSync: .tasksSync,
        .todoIsland: .todoIsland,
        .githubSearch: .githubSearch,
        .clearNotifications: .clearNotifications,
        .launcherAnswers: .launcherAnswers,
        .copyPath: .copyPath,
        .smallCommands: .smallCommands,
        .aiUsage: .aiUsage,
        .aiUsageOtherMac: .aiUsageOtherMac,
        .machLink: .machLink,
        .island: .island,
        .islandExternalDisplays: .islandExternalDisplays,
        .islandFullScreen: .islandFullScreen,
        .islandHoverOpen: .islandHoverOpen,
        .islandStatusMessages: .islandStatusMessages,
        .islandLiveActivities: .islandLiveActivities,
        .launcherFromIsland: .launcherFromIsland,
        .launcherNumberKeys: .launcherNumberKeys,
        .launcherAliasSpace: .launcherAliasSpace,
        .musicNowPlaying: .musicNowPlaying,
        .musicLastPlayer: .musicLastPlayer,
        .musicBlockAppleMusic: .musicBlockAppleMusic,
        .spotifyConnect: .spotifyConnect,
        .microphoneMute: .microphoneMute,
        .inUseMarks: .inUseMarks,
        .systemMonitor: .systemMonitor,
        .fanControl: .fanControl,
        .accessoryBatteries: .accessoryBatteries,
        .accessoryNotices: .accessoryNotices,
        .monitorAlerts: .monitorAlerts,
        .systemNotices: .systemNotices,
        .volumeLevels: .volumeLevels,
        .audioPriority: .audioPriority,
        .displayBrightness: .displayBrightness,
        .quitProtection: .quitProtection,
        .liveTimers: .liveTimers,
        .dayCalendar: .dayCalendar,
        .dayWeather: .dayWeather,
        .dayMarkets: .dayMarkets,
        .agentActions: .agentActions,
        .agentCLI: .agentCLI,
        .katana: .katana,
        .appearance: .appearance,
        .cleaningMode: .cleaningMode,
        .appUpdates: .appUpdates,
        .macUpdate: .macUpdate,
        .machRemote: .machRemote,
        .backupStatus: .backupStatus,
        .shelfBetweenMacs: .shelfBetweenMacs,
        .sendFiles: .sendFiles,
        .updateRemote: .updateRemote,
        .agentSessions: .agentSessions,
        .openBotAgents: .openBotAgents,
        .agentThreads: .agentThreads,
        .agentIsland: .agentIsland,
        .fleetPanel: .fleetPanel,
        .waitingAlerts: .waitingAlerts,
        .agentPricing: .agentPricing,
        .pastePlain: .pastePlain,
        .finderCutPaste: .finderCutPaste,
        .finderRename: .finderRename,
        .pasteImage: .pasteImage,
        .dictationIslandHUD: .dictationIslandHUD,
        .dictationCleanup: .dictationCleanup,
        .dictationHistory: .dictationHistory,
        .agentAnswer: .agentAnswer,
        .voiceAsk: .voiceAsk,
        .screenText: .screenText,
        .dictationEnglish: .dictationEnglish,
        .globeDictation: .globeDictation,
        .agentMCPServer: .agentMCPServer,
        .agentChatTools: .agentChatTools,
        .batteryChargeLimit: .batteryChargeLimit,
        .batterySailing: .batterySailing,
        .batteryHeatProtection: .batteryHeatProtection,
        .batteryCalibration: .batteryCalibration,
        .keepAwake: .keepAwake,
        .lidClosedAwake: .lidClosedAwake,
        .cleanJunk: .cleanJunk,
        .cleanHistory: .cleanHistory,
        .cleanAIData: .cleanAIData,
        .cleanDisk: .cleanDisk,
        .cleanPurge: .cleanPurge,
        .cleanOptimize: .cleanOptimize,
        .cleanSystem: .cleanSystem,
    ]

    var descriptor: Descriptor? { Self.descriptors[self] }
}
