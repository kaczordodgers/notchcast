import Foundation

extension NotchcastSettingsModule {
    var groups: [NotchcastSettingsGroup] {
        switch self {
        case .island: [
            .init(title: "Island", items: [
                .feature(.island, settings: []),
            ]),
            .init(title: "Where it shows", items: [
                .feature(.islandExternalDisplays, settings: []),
                .feature(.islandFullScreen, settings: []),
            ]),
            .init(title: "Behavior", items: [
                .feature(.islandHoverOpen, settings: [.islandHoverDelay]),
                .feature(.islandStatusMessages, settings: []),
                .feature(.islandLiveActivities, settings: []),
            ]),
        ]
        case .launcher: [
            .init(title: "Search", items: [
                .feature(.githubSearch, settings: [.launcherGitHubToken]),
                .feature(.launcherAnswers, settings: []),
                .feature(.quickLookSpace, settings: []),
            ]),
            .init(title: "Keys", items: [
                .feature(.launcherNumberKeys, settings: []),
                .feature(.launcherAliasSpace, settings: []),
                .feature(.switcherQuitKey, settings: []),
                .feature(.launcherFromIsland, settings: []),
            ]),
            .init(title: "Commands", items: [
                .feature(.clearNotifications, settings: []),
                .feature(.smallCommands, settings: []),
                .feature(.commandRunner, settings: []),
            ]),
            .init(title: "Appearance", items: [
                .feature(.appearance, settings: [.launcherAppearance]),
            ]),
        ]
        case .musicAndSound: [
            .init(title: "Amp", items: [
                .feature(.katana, settings: []),
            ]),
            .init(title: "Now playing", items: [
                .feature(.musicNowPlaying, settings: []),
                .feature(.musicLastPlayer, settings: []),
                .feature(.musicBlockAppleMusic, settings: []),
            ]),
            // ai-design-check-ignore-next-line sentence-case -- Spotify Connect is a product name.
            .init(title: "Spotify Connect", items: [
                .feature(.spotifyConnect, settings: [.musicAndSoundSpotifyConnect]),
            ]),
            .init(title: "Volume", items: [
                .feature(.volumeLevels, settings: []),
            ]),
            .init(title: "Audio devices", items: [
                .feature(.audioPriority, settings: [.musicAndSoundAudioPriority]),
            ]),
            .init(title: "Microphone", items: [
                .feature(.microphoneMute, settings: []),
                .feature(.inUseMarks, settings: [.musicAndSoundInUseFailures]),
            ]),
        ]
        case .dayAndTasks: [
            .init(title: "Day page", items: [
                .feature(.dayCalendar, settings: []),
                .feature(.dayWeather, settings: [.dayAndTasksWeatherCity]),
                .feature(.dayMarkets, settings: [.dayAndTasksMarketSymbols]),
                .feature(.eventReminder, settings: []),
            ]),
            .init(title: "Tasks", items: [
                .feature(.tasks, settings: [.dayAndTasksTaskImport]),
            ]),
            .init(title: "Timers", items: [
                .feature(.liveTimers, settings: [.dayAndTasksTimerOptions]),
            ]),
        ]
        case .monitorAndFans: [
            .init(title: "Walking pad", items: [
                .feature(.treadmillWalk, settings: []),
                .feature(.treadmillHistory, settings: []),
            ]),
            .init(title: "System monitor", items: [
                .feature(.systemMonitor, settings: []),
            ]),
            .init(title: "Fans", items: [
                .feature(.fanControl, settings: [.monitorAndFansFanMode]),
            ]),
            .init(title: "Alerts", items: [
                .feature(.monitorAlerts, settings: [.monitorAndFansAlertThresholds]),
            ]),
            .init(title: "Warnings in the island", items: [
                .feature(.lowDiskWarning, settings: []),
                .feature(.systemNotices, settings: []),
            ]),
        ]
        case .battery: [
            .init(title: "Charging", items: [
                .feature(.batteryChargeLimit, settings: [.batteryChargeLimit]),
                .feature(.batterySailing, settings: []),
                .feature(.batteryHeatProtection, settings: []),
                .feature(.batteryCalibration, settings: []),
            ]),
            .init(title: "Staying awake", items: [
                .feature(.keepAwake, settings: [.batteryAwakeDuration]),
                .feature(.lidClosedAwake, settings: []),
            ]),
            .init(title: "Accessories", items: [
                .feature(.accessoryBatteries, settings: [.batteryAccessoryReadings]),
                .feature(.accessoryNotices, settings: []),
            ]),
        ]
        case .windowsAndDisplay: [
            .init(title: "Windows", items: [
                .feature(.greenMaximize, settings: [.windowsAndDisplayExcludedApps]),
                .feature(.hideCommandM, settings: []),
                .feature(.showDesktop, settings: []),
                .feature(.spacesOrder, settings: []),
            ]),
            .init(title: "Quitting apps", items: [
                .feature(.quitProtection, settings: [.windowsAndDisplayQuitProtection]),
            ]),
            .init(title: "Trackpad", items: [
                .feature(.middleClick, settings: []),
            ]),
            .init(title: "Display", items: [
                .feature(.displayBrightness, settings: [.windowsAndDisplayBrightness]),
            ]),
        ]
        case .downloads: [
            .init(title: "Downloads", items: [
                .feature(.downloads, settings: [.downloadsFolder]),
                .feature(.downloadsAria2, settings: []),
            ]),
            .init(title: "Distill", items: [
                .feature(.distill, settings: [.downloadsDistillFolder]),
                .feature(.distillTimestamps, settings: []),
                .feature(.distillConvert, settings: []),
            ]),
            .init(title: "Torrents", items: [
                .feature(.torrents, settings: [.downloadsTorrents]),
                .feature(.torrentsUseIPhone, settings: []),
                .feature(.torrentsKeepSharing, settings: []),
            ]),
        ]
        case .filesAndClipboard: [
            .init(title: "Finder", items: [
                .feature(.finderCutPaste, settings: [.filesAndClipboardCutPasteShortcut]),
                .feature(.finderRename, settings: [.filesAndClipboardRenameShortcut]),
                .feature(.pasteImage, settings: []),
                .feature(.copyPath, settings: []),
            ]),
            .init(title: "Archives", items: [
                .feature(.archives, settings: [.filesAndClipboardArchives]),
                .feature(.archivesInPlace, settings: []),
                .feature(.archivesDefaultApp, settings: []),
            ]),
            .init(title: "Convert and compress", items: [
                .feature(.convertFiles, settings: []),
                .feature(.mediaTools, settings: []),
            ]),
            .init(title: "Clipboard", items: [
                .feature(.pastePlain, settings: []),
                .feature(.urlCleaner, settings: [.filesAndClipboardURLCleaner]),
            ]),
            .init(title: "Text editor", items: [
                .feature(.markdownFiles, settings: []),
                .feature(.plainTextFiles, settings: []),
                .feature(.editorSpellChecking, settings: []),
            ]),
        ]
        case .capture: [
            .init(title: "Screenshots", items: [
                .feature(.screenshot, settings: [.captureScreenshotDestination]),
                .feature(.scrollingCapture, settings: []),
                .feature(.screenText, settings: [.captureScreenTextLineBreaks]),
                .feature(.captureEditor, settings: []),
            ]),
            // ai-design-check-ignore-next-line sentence-case -- Matches the feature row title.
            .init(title: "Color Picker", items: [
                .feature(.colorPicker, settings: [.captureColorFormat]),
            ]),
            .init(title: "Recording", items: [
                .feature(.recording, settings: [.captureRecordingOptions]),
                .feature(.captureTrimmer, settings: []),
            ]),
        ]
        case .dictation: [
            .init(title: "Dictation", items: [
                .feature(.globeDictation, settings: []),
                .feature(.dictationIslandHUD, settings: []),
            ]),
            .init(title: "Text", items: [
                .feature(.dictationEnglish, settings: []),
                .feature(.dictationCleanup, settings: [.dictationCleanup]),
            ]),
            .init(title: "History", items: [
                .feature(.dictationHistory, settings: []),
            ]),
        ]
        case .aiAndAgents: [
            .init(title: "AI usage", items: [
                .feature(.aiUsage, settings: [.aiAndAgentsUsageCache]),
                .feature(.aiUsageOtherMac, settings: []),
                .feature(.agentSessions, settings: []),
                .feature(.agentPricing, settings: []),
                .feature(.buildStats, settings: [.aiAndAgentsBuildSnapshot]),
            ]),
            .init(title: "Agents", items: [
                .feature(.agentActions, settings: []),
                .feature(.agentConfirmation, settings: []),
                .feature(.agentCLI, settings: [.aiAndAgentsCLIInstall]),
                .feature(.agentMCPServer, settings: []),
                .feature(.agentChatTools, settings: [.aiAndAgentsChatTools]),
                .feature(.agentAnswer, settings: []),
                .feature(.voiceAsk, settings: [.aiAndAgentsVoiceDestination]),
            ]),
        ]
        case .twoMacs: [
            .init(title: "Connection", items: [
                .feature(.machLink, settings: [.twoMacsConnection]),
                .feature(.linkHealth, settings: []),
                .feature(.linkQuickFixes, settings: []),
            ]),
            // ai-design-check-ignore-next-line sentence-case -- Mac is a product name.
            .init(title: "Remote Mac", items: [
                .feature(.machRemote, settings: [.twoMacsRemotePaths]),
                .feature(.sendFiles, settings: []),
                .feature(.updateRemote, settings: []),
                .feature(.remoteScreen, settings: []),
                .feature(.machMBPFans, settings: []),
                .feature(.machBlockedDialogAlert, settings: []),
            ]),
            .init(title: "Sharing", items: [
                .feature(.shelfBetweenMacs, settings: []),
            ]),
        ]
        case .backups: [
            .init(title: "Notchcast settings", items: [
                .feature(.settingsBackup, settings: []),
            ]),
            .init(title: "Mac backup", items: [
                .feature(.backupStatus, settings: [.backupsStatusPath]),
                .feature(.backupRunNow, settings: []),
                .feature(.backupBrowseRestore, settings: []),
            ]),
            .init(title: "Setup", items: [
                .feature(.machineSetupProfile, settings: []),
            ]),
        ]
        case .cleanAndUpdates: [
            .init(title: "Clean", items: [
                .feature(.cleanJunk, settings: [.cleanAndUpdatesJunk]),
                .feature(.cleanHistory, settings: [.cleanAndUpdatesHistory]),
                .feature(.cleanAIData, settings: [.cleanAndUpdatesAIData]),
                .feature(.cleanDisk, settings: [.cleanAndUpdatesDisk]),
                .feature(.cleanPurge, settings: [.cleanAndUpdatesPurge]),
                .feature(.cleanOptimize, settings: [.cleanAndUpdatesOptimize]),
                .feature(.cleanSystem, settings: [.cleanAndUpdatesSystem]),
            ]),
            .init(title: "Updates", items: [
                .feature(.appUpdates, settings: [.cleanAndUpdatesAppUpdates]),
                .feature(.macUpdate, settings: [.cleanAndUpdatesMacUpdate]),
            ]),
            .init(title: "Cleaning", items: [
                .feature(.cleaningMode, settings: [.cleanAndUpdatesCleaningMode]),
            ]),
        ]
        case .tweaks: [
            .init(title: "Typing", items: [
                .feature(.typingTweaks, settings: [.tweaksTyping]),
            ]),
            .init(title: "Finder", items: [
                .feature(.finderTweaks, settings: [.tweaksFinder]),
            ]),
            .init(title: "Dock and windows", items: [
                .feature(.dockTweaks, settings: [.tweaksDock]),
            ]),
        ]
        case .privacyAndStartup: [
            .init(title: "Startup", items: [
                .feature(.startupItems, settings: [.privacyAndStartupLaunchAgents]),
                .feature(.notificationCleanup, settings: []),
            ]),
            .init(title: "Security", items: [
                .feature(.sudoTouchID, settings: []),
                .feature(.spotlightOff, settings: []),
                .feature(.privacyChoices, settings: []),
                .feature(.aiFeaturesOff, settings: []),
            ]),
            .init(title: "Apple apps", items: [
                .feature(.appleAppsTweaks, settings: [.privacyAndStartupAppleApps]),
            ]),
            .init(title: "iPhone backup", items: [
                .feature(.iPhoneBackupTweaks, settings: [.privacyAndStartupIPhoneBackup]),
            ]),
            .init(title: "Tools", items: [
                .feature(.killProcess, settings: []),
                .feature(.macSetup, settings: []),
            ]),
        ]
        }
    }
}
