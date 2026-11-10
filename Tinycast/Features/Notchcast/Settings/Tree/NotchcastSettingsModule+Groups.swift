import Foundation

extension NotchcastSettingsModule {
    var groups: [NotchcastSettingsGroup] {
        switch self {
        case .island: [
            .init(title: LocalizedStringResource("Island", table: "Notchcast"), items: [
                .feature(.island, settings: []),
            ]),
            .init(title: LocalizedStringResource("Where it shows", table: "Notchcast"), items: [
                .feature(.islandExternalDisplays, settings: []),
                .feature(.islandFullScreen, settings: []),
            ]),
            .init(title: LocalizedStringResource("Behavior", table: "Notchcast"), items: [
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
            .init(title: LocalizedStringResource("Keys", table: "Notchcast"), items: [
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
            .init(title: LocalizedStringResource("Amp", table: "Notchcast"), items: [
                .feature(.katana, settings: []),
            ]),
            .init(title: LocalizedStringResource("Now playing", table: "Notchcast"), items: [
                .feature(.musicNowPlaying, settings: []),
                .feature(.musicLastPlayer, settings: []),
                .feature(.musicBlockAppleMusic, settings: []),
            ]),
            // ai-design-check-ignore-next-line sentence-case -- Spotify Connect is a product name.
            .init(title: LocalizedStringResource("Spotify Connect", table: "Notchcast"), items: [
                .feature(.spotifyConnect, settings: [.musicAndSoundSpotifyConnect]),
            ]),
            .init(title: "Volume", items: [
                .feature(.volumeLevels, settings: []),
            ]),
            .init(title: LocalizedStringResource("Audio devices", table: "Notchcast"), items: [
                .feature(.audioPriority, settings: [.musicAndSoundAudioPriority]),
            ]),
            .init(title: "Microphone", items: [
                .feature(.microphoneMute, settings: []),
                .feature(.inUseMarks, settings: [.musicAndSoundInUseFailures]),
            ]),
        ]
        case .dayAndTasks: [
            .init(title: LocalizedStringResource("Day page", table: "Notchcast"), items: [
                .feature(.dayCalendar, settings: []),
                .feature(.dayWeather, settings: [.dayAndTasksWeatherCity]),
                .feature(.dayMarkets, settings: [.dayAndTasksMarketSymbols]),
                .feature(.eventReminder, settings: []),
            ]),
            .init(title: LocalizedStringResource("Tasks", table: "Notchcast"), items: [
                .feature(.todoIsland, settings: []),
                .feature(.tasks, settings: [.dayAndTasksTaskImport]),
                .feature(.tasksSync, settings: []),
            ]),
            .init(title: LocalizedStringResource("Timers", table: "Notchcast"), items: [
                .feature(.liveTimers, settings: [.dayAndTasksTimerOptions]),
            ]),
        ]
        case .monitorAndFans: [
            .init(title: LocalizedStringResource("Walking pad", table: "Notchcast"), items: [
                .feature(.treadmillWalk, settings: []),
                .feature(.treadmillHistory, settings: []),
            ]),
            .init(title: LocalizedStringResource("System monitor", table: "Notchcast"), items: [
                .feature(.systemMonitor, settings: []),
            ]),
            .init(title: LocalizedStringResource("Fans", table: "Notchcast"), items: [
                .feature(.fanControl, settings: [.monitorAndFansFanMode]),
            ]),
            .init(title: LocalizedStringResource("Alerts", table: "Notchcast"), items: [
                .feature(.monitorAlerts, settings: [.monitorAndFansAlertThresholds]),
            ]),
            .init(title: LocalizedStringResource("Warnings in the island", table: "Notchcast"), items: [
                .feature(.lowDiskWarning, settings: []),
                .feature(.systemNotices, settings: []),
            ]),
        ]
        case .battery: [
            .init(title: LocalizedStringResource("Charging", table: "Notchcast"), items: [
                .feature(.batteryChargeLimit, settings: [.batteryChargeLimit]),
                .feature(.batterySailing, settings: []),
                .feature(.batteryHeatProtection, settings: []),
                .feature(.batteryCalibration, settings: []),
            ]),
            .init(title: LocalizedStringResource("Staying awake", table: "Notchcast"), items: [
                .feature(.keepAwake, settings: [.batteryAwakeDuration]),
                .feature(.lidClosedAwake, settings: []),
            ]),
            .init(title: LocalizedStringResource("Accessories", table: "Notchcast"), items: [
                .feature(.accessoryBatteries, settings: [.batteryAccessoryReadings]),
                .feature(.accessoryNotices, settings: []),
            ]),
        ]
        case .windowsAndDisplay: [
            .init(title: LocalizedStringResource("Windows", table: "Notchcast"), items: [
                .feature(.greenMaximize, settings: [.windowsAndDisplayExcludedApps]),
                .feature(.hideCommandM, settings: []),
                .feature(.showDesktop, settings: []),
                .feature(.spacesOrder, settings: []),
            ]),
            .init(title: LocalizedStringResource("Quitting apps", table: "Notchcast"), items: [
                .feature(.quitProtection, settings: [.windowsAndDisplayQuitProtection]),
            ]),
            .init(title: LocalizedStringResource("Trackpad", table: "Notchcast"), items: [
                .feature(.middleClick, settings: []),
            ]),
            .init(title: "Display", items: [
                .feature(.displayBrightness, settings: [.windowsAndDisplayBrightness]),
            ]),
        ]
        case .downloads: [
            .init(title: LocalizedStringResource("Downloads", table: "Notchcast"), items: [
                .feature(.downloads, settings: [.downloadsFolder]),
                .feature(.downloadsAria2, settings: []),
            ]),
            .init(title: LocalizedStringResource("Distill", table: "Notchcast"), items: [
                .feature(.distill, settings: [.downloadsDistillFolder]),
                .feature(.distillTimestamps, settings: []),
                .feature(.distillConvert, settings: []),
            ]),
            .init(title: LocalizedStringResource("Torrents", table: "Notchcast"), items: [
                .feature(.torrents, settings: [.downloadsTorrents]),
                .feature(.torrentsUseIPhone, settings: []),
                .feature(.torrentsKeepSharing, settings: []),
            ]),
        ]
        case .filesAndClipboard: [
            .init(title: LocalizedStringResource("Finder", table: "Notchcast"), items: [
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
            .init(title: LocalizedStringResource("Convert and compress", table: "Notchcast"), items: [
                .feature(.convertFiles, settings: []),
                .feature(.mediaTools, settings: []),
            ]),
            .init(title: "Clipboard", items: [
                .feature(.pastePlain, settings: []),
                .feature(.urlCleaner, settings: [.filesAndClipboardURLCleaner]),
            ]),
            .init(title: LocalizedStringResource("Text editor", table: "Notchcast"), items: [
                .feature(.markdownFiles, settings: []),
                .feature(.plainTextFiles, settings: []),
                .feature(.editorSpellChecking, settings: []),
            ]),
        ]
        case .capture: [
            .init(title: LocalizedStringResource("Screenshots", table: "Notchcast"), items: [
                .feature(.screenshot, settings: [.captureScreenshotDestination]),
                .feature(.scrollingCapture, settings: []),
                .feature(.screenText, settings: [.captureScreenTextLineBreaks]),
                .feature(.captureEditor, settings: []),
            ]),
            // ai-design-check-ignore-next-line sentence-case -- Matches the feature row title.
            .init(title: LocalizedStringResource("Color Picker", table: "Notchcast"), items: [
                .feature(.colorPicker, settings: [.captureColorFormat]),
            ]),
            .init(title: LocalizedStringResource("Recording", table: "Notchcast"), items: [
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
                .setting(.dictationHistory),
            ]),
        ]
        case .aiAndAgents: [
            .init(title: LocalizedStringResource("AI usage", table: "Notchcast"), items: [
                .feature(.aiUsage, settings: [.aiAndAgentsUsageCache]),
                .feature(.aiUsageOtherMac, settings: []),
                .feature(.agentSessions, settings: []),
                .feature(.agentPricing, settings: []),
                .feature(.buildStats, settings: [.aiAndAgentsBuildSnapshot]),
            ]),
            .init(title: LocalizedStringResource("Agents", table: "Notchcast"), items: [
                .feature(.agentThreads, settings: []),
                .feature(.agentIsland, settings: []),
                .feature(.fleetPanel, settings: []),
                .feature(.waitingAlerts, settings: []),
                .feature(.agentActions, settings: []),
                .feature(.agentConfirmation, settings: []),
                .feature(.agentCLI, settings: [.aiAndAgentsCLIInstall]),
                .feature(.agentMCPServer, settings: []),
                .feature(.agentChatTools, settings: [.aiAndAgentsChatTools]),
                .feature(.voiceAsk, settings: [.aiAndAgentsVoiceDestination]),
                .feature(.openBotAgents, settings: []),
            ]),
        ]
        case .twoMacs: [
            .init(title: "Connection", items: [
                .feature(.machLink, settings: [.twoMacsConnection]),
                .feature(.linkHealth, settings: []),
                .feature(.linkQuickFixes, settings: []),
            ]),
            // ai-design-check-ignore-next-line sentence-case -- Mac is a product name.
            .init(title: LocalizedStringResource("Remote Mac", table: "Notchcast"), items: [
                .feature(.machRemote, settings: [.twoMacsRemotePaths]),
                .feature(.sendFiles, settings: []),
                .feature(.updateRemote, settings: []),
                .feature(.remoteScreen, settings: []),
                .feature(.machMBPFans, settings: []),
                .feature(.machBlockedDialogAlert, settings: []),
            ]),
            .init(title: LocalizedStringResource("Sharing", table: "Notchcast"), items: [
                .feature(.shelfBetweenMacs, settings: []),
            ]),
        ]
        case .backups: [
            .init(title: LocalizedStringResource("Notchcast settings", table: "Notchcast"), items: [
                .feature(.settingsBackup, settings: []),
            ]),
            .init(title: LocalizedStringResource("Mac backup", table: "Notchcast"), items: [
                .feature(.backupStatus, settings: [.backupsStatusPath]),
                .feature(.backupRunNow, settings: []),
                .feature(.backupBrowseRestore, settings: []),
            ]),
            .init(title: LocalizedStringResource("Setup", table: "Notchcast"), items: [
                .feature(.machineSetupProfile, settings: []),
            ]),
        ]
        case .cleanAndUpdates: [
            .init(title: LocalizedStringResource("Clean", table: "Notchcast"), items: [
                .feature(.cleanJunk, settings: [.cleanAndUpdatesJunk]),
                .feature(.cleanHistory, settings: [.cleanAndUpdatesHistory]),
                .feature(.cleanAIData, settings: [.cleanAndUpdatesAIData]),
                .feature(.cleanDisk, settings: [.cleanAndUpdatesDisk]),
                .feature(.cleanPurge, settings: [.cleanAndUpdatesPurge]),
                .feature(.cleanOptimize, settings: [.cleanAndUpdatesOptimize]),
                .feature(.cleanSystem, settings: [.cleanAndUpdatesSystem]),
            ]),
            .init(title: LocalizedStringResource("Updates", table: "Notchcast"), items: [
                .feature(.appUpdates, settings: [.cleanAndUpdatesAppUpdates]),
                .feature(.macUpdate, settings: [.cleanAndUpdatesMacUpdate]),
            ]),
            .init(title: LocalizedStringResource("Cleaning", table: "Notchcast"), items: [
                .feature(.cleaningMode, settings: [.cleanAndUpdatesCleaningMode]),
            ]),
        ]
        case .tweaks: [
            .init(title: LocalizedStringResource("Typing", table: "Notchcast"), items: [
                .feature(.typingTweaks, settings: [.tweaksTyping]),
            ]),
            .init(title: LocalizedStringResource("Finder", table: "Notchcast"), items: [
                .feature(.finderTweaks, settings: [.tweaksFinder]),
            ]),
            .init(title: LocalizedStringResource("Dock and windows", table: "Notchcast"), items: [
                .feature(.dockTweaks, settings: [.tweaksDock]),
            ]),
        ]
        case .privacyAndStartup: [
            .init(title: LocalizedStringResource("Startup", table: "Notchcast"), items: [
                .feature(.startupItems, settings: [.privacyAndStartupLaunchAgents]),
                .feature(.notificationCleanup, settings: []),
            ]),
            .init(title: LocalizedStringResource("Security", table: "Notchcast"), items: [
                .feature(.sudoTouchID, settings: []),
                .feature(.spotlightOff, settings: []),
                .feature(.privacyChoices, settings: []),
                .feature(.aiFeaturesOff, settings: []),
            ]),
            .init(title: LocalizedStringResource("Apple apps", table: "Notchcast"), items: [
                .feature(.appleAppsTweaks, settings: [.privacyAndStartupAppleApps]),
            ]),
            .init(title: LocalizedStringResource("iPhone backup", table: "Notchcast"), items: [
                .feature(.iPhoneBackupTweaks, settings: [.privacyAndStartupIPhoneBackup]),
            ]),
        ]
        }
    }
}
