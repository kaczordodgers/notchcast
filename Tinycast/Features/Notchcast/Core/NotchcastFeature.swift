import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case tasks
    case tasksSync
    case todoIsland
    case githubSearch
    case clearNotifications
    case launcherAnswers
    case copyPath
    case smallCommands
    case aiUsage
    case aiUsageOtherMac
    case machLink
    case island
    case islandExternalDisplays
    case islandFullScreen
    case islandHoverOpen
    case islandStatusMessages
    case islandLiveActivities
    case launcherFromIsland
    case launcherNumberKeys
    case launcherAliasSpace
    case musicNowPlaying
    case musicLastPlayer
    case musicBlockAppleMusic
    case spotifyConnect
    case microphoneMute
    case inUseMarks
    case systemMonitor
    case fanControl
    case accessoryBatteries
    case accessoryNotices
    case monitorAlerts
    case lowDiskWarning
    case systemNotices
    case volumeLevels
    case audioPriority
    case displayBrightness
    case quitProtection
    case liveTimers
    case dayCalendar
    case dayWeather
    case dayMarkets
    case agentActions
    case agentCLI
    case treadmillWalk
    case treadmillHistory
    case katana
    case appearance
    case cleaningMode
    case appUpdates
    case macUpdate
    case machRemote
    case backupStatus
    case linkHealth
    case shelfBetweenMacs
    case sendFiles
    case updateRemote
    case agentSessions
    case openBotAgents
    case agentThreads
    case agentIsland
    case fleetPanel
    case waitingAlerts
    case agentPricing
    case pastePlain
    case finderCutPaste
    case finderRename
    case pasteImage
    case colorPicker
    case screenshot
    case dictationIslandHUD
    case dictationCleanup
    case dictationHistory
    case captureTrimmer
    case captureEditor
    case agentAnswer
    case voiceAsk
    case recording
    case screenText
    case scrollingCapture
    case dictationEnglish
    case globeDictation
    case agentMCPServer
    case agentChatTools
    case batteryChargeLimit
    case batterySailing
    case batteryHeatProtection
    case batteryCalibration
    case keepAwake
    case lidClosedAwake
    case cleanJunk
    case cleanHistory
    case cleanAIData
    case cleanDisk
    case cleanPurge
    case cleanOptimize
    case cleanSystem
    case settingsBackup
    case showDesktop
    case spacesOrder
    case hideCommandM
    case middleClick
    case greenMaximize
    case machineSetupProfile
    case agentConfirmation
    case eventReminder
    case switcherQuitKey
    case linkQuickFixes
    case startupItems
    case notificationCleanup
    case sudoTouchID
    case killProcess
    case macSetup
    case aiFeaturesOff
    case spotlightOff
    case privacyChoices
    case typingTweaks
    case finderTweaks
    case dockTweaks
    case appleAppsTweaks
    case iPhoneBackupTweaks
    case downloads
    case downloadsAria2
    case distill
    case distillTimestamps
    case distillConvert

    case urlCleaner

    case convertFiles

    case mediaTools

    case commandRunner
    case machBlockedDialogAlert
    case remoteScreen
    case machMBPFans
    case archives
    case archivesInPlace
    case archivesDefaultApp
    case torrents
    case torrentsUseIPhone
    case torrentsKeepSharing
    case backupRunNow
    case backupBrowseRestore
    case quickLookSpace
    case markdownFiles
    case plainTextFiles
    case editorSpellChecking
    case buildStats

    var dependencies: [Self] {
        if let descriptor { return descriptor.dependencies }
        return switch self {
        case .archives: []
        case .archivesInPlace: [.archives]
        case .archivesDefaultApp: [.archives]
        case .torrents: []
        case .torrentsUseIPhone: [.torrents]
        case .torrentsKeepSharing: [.torrents]
        default: needsIsland ? [.island] : []
        }
    }

    var settingsGroup: SettingsGroup {
        if let descriptor { return descriptor.group }
        return switch self {
        case .commandRunner: .launcher
        case .mediaTools: .activities
        case .convertFiles: .activities
        case .urlCleaner: .system
        case .buildStats: .buildStats
        case .colorPicker: .captureAndDictation
        case .scrollingCapture: .captureAndDictation
        case .screenshot: .captureAndDictation
        case .machBlockedDialogAlert: .system
        case .remoteScreen: .system
        case .machMBPFans: .system
        case .captureTrimmer: .captureAndDictation
        case .captureEditor: .captureAndDictation
        case .recording: .captureAndDictation
        case .backupRunNow: .system
        case .backupBrowseRestore: .system
        case .quickLookSpace: .launcher
        case .markdownFiles: .system
        case .plainTextFiles: .system
        case .editorSpellChecking: .system
        case .settingsBackup: .system
        case .showDesktop: .system
        case .spacesOrder: .system
        case .middleClick: .system
        case .greenMaximize: .system
        case .machineSetupProfile: .system
        case .agentConfirmation: .islandOptions
        case .switcherQuitKey: .launcher
        case .treadmillWalk: .activities
        case .treadmillHistory: .activities
        case .startupItems: .tweaks
        case .notificationCleanup: .tweaks
        case .sudoTouchID: .tweaks
        case .killProcess: .tweaks
        case .macSetup: .tweaks
        case .aiFeaturesOff: .tweaks
        case .spotlightOff: .tweaks
        case .privacyChoices: .tweaks
        case .typingTweaks: .tweaks
        case .finderTweaks: .tweaks
        case .dockTweaks: .tweaks
        case .appleAppsTweaks: .tweaks
        case .iPhoneBackupTweaks: .tweaks
        case .downloads: .activities
        case .downloadsAria2: .activities
        case .distill: .activities
        case .distillTimestamps: .activities
        case .distillConvert: .activities
        case .archives: .archives
        case .archivesInPlace: .archives
        case .archivesDefaultApp: .archives
        case .torrents: .torrents
        case .torrentsUseIPhone: .torrents
        case .torrentsKeepSharing: .torrents
        default: preconditionFailure("\(self) has neither a descriptor nor a settingsGroup arm")
        }
    }

    var title: String {
        if let descriptor { return descriptor.title }
        return switch self {
        case .commandRunner: String(localized: "Command Runner", table: "Notchcast")
        case .mediaTools: String(localized: "Media Tools", table: "Notchcast")
        case .convertFiles: String(localized: "Convert Files", table: "Notchcast")
        case .urlCleaner: String(localized: "URL cleaner", table: "Notchcast")
        case .buildStats: String(localized: "Build statistics", table: "Notchcast")
        case .treadmillWalk: String(localized: "Walking Pad", table: "Notchcast")
        case .treadmillHistory: String(localized: "Walk History", table: "Notchcast")
        case .colorPicker: String(localized: "Color Picker", table: "Notchcast")
        case .screenshot: String(localized: "Screenshots", table: "Notchcast")
        case .scrollingCapture: String(localized: "Scrolling Capture", table: "Notchcast")
        case .greenMaximize: String(localized: "Green Button Maximizes", table: "Notchcast")
        case .middleClick: String(localized: "Trackpad Middle Click", table: "Notchcast")
        case .spacesOrder: String(localized: "Keep Spaces in a fixed order", table: "Notchcast")
        case .showDesktop: String(localized: "Show Desktop with F3", table: "Notchcast")
        case .startupItems: String(localized: "Startup Items", table: "Notchcast")
        case .notificationCleanup: String(localized: "Notification Cleanup", table: "Notchcast")
        case .sudoTouchID: String(localized: "Touch ID for sudo", table: "Notchcast")
        case .killProcess: String(localized: "Kill Process", table: "Notchcast")
        case .macSetup: String(localized: "Mac Setup Presets", table: "Notchcast")
        case .aiFeaturesOff: String(localized: "AI Features Off", table: "Notchcast")
        case .spotlightOff: String(localized: "Spotlight Indexing Off", table: "Notchcast")
        case .privacyChoices: String(localized: "Privacy Choices", table: "Notchcast")
        case .typingTweaks: String(localized: "Typing", table: "Notchcast")
        case .finderTweaks: String(localized: "Finder", table: "Notchcast")
        case .dockTweaks: String(localized: "Dock and windows", table: "Notchcast")
        case .appleAppsTweaks: String(localized: "Apple apps", table: "Notchcast")
        case .iPhoneBackupTweaks: String(localized: "iPhone backup", table: "Notchcast")
        case .archives: String(localized: "Archives")
        case .archivesInPlace: String(localized: "Extract in place", table: "Notchcast")
        case .archivesDefaultApp: String(localized: "Open archives with Notchcast", table: "Notchcast")
        case .torrents: String(localized: "Torrents", table: "Notchcast")
        case .torrentsUseIPhone: String(localized: "Use a plugged-in iPhone for big downloads", table: "Notchcast")
        case .torrentsKeepSharing: String(localized: "Keep sharing until ratio 1.0", table: "Notchcast")
        case .captureTrimmer: String(localized: "Recording Trimmer", table: "Notchcast")
        case .captureEditor: String(localized: "Capture Editor", table: "Notchcast")
        case .recording: String(localized: "Screen Recording", table: "Notchcast")
        case .settingsBackup: String(localized: "Settings Backup", table: "Notchcast")
        case .machineSetupProfile: String(localized: "Machine Setup Profile", table: "Notchcast")
        case .agentConfirmation: String(localized: "Agent Confirmation", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Switcher Quit Key", table: "Notchcast")
        case .downloads: String(localized: "Downloads", table: "Notchcast")
        case .downloadsAria2: String(localized: "Fast Downloads with aria2c", table: "Notchcast")
        case .distill: String(localized: "Distill", table: "Notchcast")
        case .distillTimestamps: String(localized: "Distill Timestamps", table: "Notchcast")
        case .distillConvert: String(localized: "Convert Distill Folder", table: "Notchcast")
        case .machBlockedDialogAlert: String(localized: "Other Mac Dialog Alerts", table: "Notchcast")
        case .remoteScreen: String(localized: "Remote Screen", table: "Notchcast")
        case .machMBPFans: String(localized: "Other Mac Fans", table: "Notchcast")
        case .backupRunNow: String(localized: "Back Up Now", table: "Notchcast")
        case .backupBrowseRestore: String(localized: "Browse and Restore Backups", table: "Notchcast")
        case .quickLookSpace: String(localized: "Quick Look on Space", table: "Notchcast")
        case .markdownFiles: String(localized: "Markdown Files", table: "Notchcast")
        case .plainTextFiles: String(localized: "Plain Text Files", table: "Notchcast")
        case .editorSpellChecking: String(localized: "Editor Spell Checking", table: "Notchcast")
        default: preconditionFailure("\(self) has neither a descriptor nor a title arm")
        }
    }

    var subtitle: String {
        if let descriptor { return descriptor.subtitle }
        return switch self {
        case .commandRunner: String(localized: "Run commands from a host profile.", table: "Notchcast")
        case .mediaTools: String(localized: "Compress media, make GIFs and extract text locally.", table: "Notchcast")
        case .convertFiles: String(localized: "Convert local files beside the originals.", table: "Notchcast")
        case .urlCleaner: String(localized: "Remove tracking parameters from copied links.", table: "Notchcast")
        case .buildStats: String(localized: "Read a local build snapshot.", table: "Notchcast")
        case .treadmillWalk: String(localized: "Control a Bluetooth walking pad from the launcher.", table: "Notchcast")
        case .treadmillHistory: String(localized: "Keep walk totals, daily goals and lubrication reminders.", table: "Notchcast")
        case .colorPicker: String(localized: "Copy a color from anywhere on the screen.", table: "Notchcast")
        case .screenshot: String(localized: "Capture an area, window or display.", table: "Notchcast")
        case .scrollingCapture: String(localized: "Copy a scrolling area as one image.", table: "Notchcast")
        case .greenMaximize: String(localized: "Click the green button to maximize or restore; hold Option for macOS behavior.", table: "Notchcast")
        case .middleClick: String(localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.", table: "Notchcast")
        case .spacesOrder: String(localized: "Prevent automatic Spaces reordering and restore your setting when turned off.", table: "Notchcast")
        case .showDesktop: String(localized: "Press F3 to show the desktop; press again to restore windows.", table: "Notchcast")
        case .startupItems: String(localized: "Manage user LaunchAgents and inspect system items.", table: "Notchcast")
        case .notificationCleanup: String(localized: "Dismiss disk-ejection alerts automatically.", table: "Notchcast")
        case .sudoTouchID: String(localized: "Use Touch ID to authorize sudo.", table: "Notchcast")
        case .killProcess: String(localized: "Adds a command to stop a process.", table: "Notchcast")
        case .macSetup: String(localized: "Apply reversible macOS preferences.", table: "Notchcast")
        case .aiFeaturesOff: String(localized: "Choose which Apple intelligence features to disable.", table: "Notchcast")
        case .spotlightOff: String(localized: "Turn off Spotlight indexing.", table: "Notchcast")
        case .privacyChoices: String(localized: "Choose macOS privacy restrictions.", table: "Notchcast")
        case .typingTweaks: String(localized: "Changes system preferences after confirmation; some changes require signing out.", table: "Notchcast")
        case .finderTweaks: String(localized: "Changes Finder preferences and restarts Finder after confirmation.", table: "Notchcast")
        case .dockTweaks: String(localized: "Changes Dock preferences and restarts Dock after confirmation.", table: "Notchcast")
        case .appleAppsTweaks: String(localized: "macOS requires your approval to install this restriction; remove it in System Settings.", table: "Notchcast")
        case .iPhoneBackupTweaks: String(localized: "Changes system preferences after confirmation; some changes require signing out.", table: "Notchcast")
        case .archives: String(localized: "Extract opened archives beside the original file.", table: "Notchcast")
        case .archivesInPlace: String(localized: "The archive shrinks while extracting.", table: "Notchcast")
        case .archivesDefaultApp: String(localized: "Use Notchcast instead of Archive Utility to open archives.", table: "Notchcast")
        case .torrents: String(localized: "Download magnet links and torrent files to Downloads.", table: "Notchcast")
        case .torrentsUseIPhone: String(localized: "Use Wi-Fi and iPhone USB Personal Hotspot together.", table: "Notchcast")
        case .torrentsKeepSharing: String(localized: "Upload as much as you download before stopping.", table: "Notchcast")
        case .captureTrimmer: String(localized: "Trim recordings and export MP4 or GIF files.", table: "Notchcast")
        case .captureEditor: String(localized: "Mark up a capture and copy it.", table: "Notchcast")
        case .recording: String(localized: "Record an area, window or display with system audio.", table: "Notchcast")
        case .settingsBackup: String(localized: "Back up safe Notchcast preferences daily.", table: "Notchcast")
        case .machineSetupProfile: String(localized: "Plan portable setup imports and exports.", table: "Notchcast")
        case .agentConfirmation: String(localized: "Ask before allowing agent requests.", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Press Q in an empty window search to quit the selected app.", table: "Notchcast")
        case .downloads: String(localized: "Download video, audio, transcripts and webpages from clipboard links.", table: "Notchcast")
        case .downloadsAria2: String(localized: "Use aria2c for faster media downloads when it is installed.", table: "Notchcast")
        case .distill: String(localized: "Save links and transcribe media into your Distill folder.", table: "Notchcast")
        case .distillTimestamps: String(localized: "Include approximate chunk timestamps in Distill transcripts.", table: "Notchcast")
        case .distillConvert: String(localized: "Convert files in your Distill folder to Markdown or text.", table: "Notchcast")
        case .machBlockedDialogAlert: String(localized: "Check for system dialogs on the paired Mac on demand.", table: "Notchcast")
        case .remoteScreen: String(localized: "Request screen sharing with the paired Mac.", table: "Notchcast")
        case .machMBPFans: String(localized: "Control fans on the paired Mac.", table: "Notchcast")
        case .backupRunNow: String(localized: "Allow starting the configured backup job.", table: "Notchcast")
        case .backupBrowseRestore: String(localized: "Browse snapshots and restore into a new Downloads folder.", table: "Notchcast")
        case .quickLookSpace: String(localized: "Preview an arrow-selected file with Space.", table: "Notchcast")
        case .markdownFiles: String(localized: "Edit Markdown documents outside the notes folder.", table: "Notchcast")
        case .plainTextFiles: String(localized: "Edit plain text while preserving its file encoding.", table: "Notchcast")
        case .editorSpellChecking: String(localized: "Check spelling in the editor.", table: "Notchcast")
        default: preconditionFailure("\(self) has neither a descriptor nor a subtitle arm")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        if let descriptor { return descriptor.requiredGrants }
        return switch self {
        case .scrollingCapture: [.screenRecording]
        case .screenshot: [.screenRecording]
        case .showDesktop: [.accessibility]
        case .middleClick: [.accessibility]
        case .greenMaximize: [.accessibility]
        case .switcherQuitKey: [.accessibility]
        case .recording: [.screenRecording]
        case .notificationCleanup: [.accessibility]
        case .startupItems: []
        case .sudoTouchID: []
        case .killProcess: []
        case .macSetup: []
        case .aiFeaturesOff: []
        case .spotlightOff: []
        case .privacyChoices: []
        case .typingTweaks: []
        case .finderTweaks: []
        case .dockTweaks: []
        case .appleAppsTweaks: []
        case .iPhoneBackupTweaks: []
        default: []
        }
    }
}

extension NotchcastFeature {
    var isWired: Bool {
        !Self.unwired.contains(self)
    }

    /// Switches kept out of Settings until a user can reach them; the code stays.
    /// Each reason is in notchcast/switch-path-allowlist-*.json. Unhide = delete its line.
    static let unwired: Set<Self> = [
        .todoIsland,
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
        .backupRunNow,
        .backupBrowseRestore,
        .markdownFiles,
        .plainTextFiles,
        .buildStats,
        .killProcess,
        .launcherAnswers,
        .agentAnswer,
        .remoteScreen,
        .machMBPFans,
        .macSetup,
        .machineSetupProfile,
        .commandRunner,
    ]

    static var systemToolsSettingsFeatures: [Self] {
        [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess,
         .macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices].filter(\.isWired)
    }

    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        if let descriptor { return descriptor.dependencies.contains(.island) }
        if isSystemFeature || isSystemTweak || settingsGroup == .clean { return false }
        return switch self {
        case .colorPicker: false
        case .scrollingCapture: false
        case .screenshot: false
        case .buildStats: false
        case .urlCleaner: false
        case .convertFiles: false
        case .mediaTools: false
        case .commandRunner: false
        case .settingsBackup: false
        case .showDesktop: false
        case .spacesOrder: false
        case .middleClick: false
        case .greenMaximize: false
        case .machineSetupProfile: false
        case .switcherQuitKey: false
        case .archives: false
        case .archivesInPlace: false
        case .archivesDefaultApp: false
        case .torrents: false
        case .torrentsUseIPhone: false
        case .torrentsKeepSharing: false
        case .captureTrimmer: false
        case .captureEditor: false
        case .recording: false
        case .treadmillWalk: false
        case .treadmillHistory: false
        case .downloads: false
        case .downloadsAria2: false
        case .distill: false
        case .distillTimestamps: false
        case .distillConvert: false
        case .remoteScreen: false
        case .machMBPFans: false
        case .backupRunNow: false
        case .backupBrowseRestore: false
        case .quickLookSpace: false
        case .markdownFiles: false
        case .plainTextFiles: false
        case .editorSpellChecking: false
        default: true
        }
    }

    var isSystemTweak: Bool {
        if let descriptor { return descriptor.isSystemTweak }
        return switch self {
        case .startupItems: true
        case .notificationCleanup: true
        case .sudoTouchID: true
        case .killProcess: true
        case .macSetup: true
        case .aiFeaturesOff: true
        case .spotlightOff: true
        case .privacyChoices: true
        case .typingTweaks: true
        case .finderTweaks: true
        case .dockTweaks: true
        case .appleAppsTweaks: true
        case .iPhoneBackupTweaks: true
        default: false
        }
    }

    var defaultEnabled: Bool {
        if let descriptor { return descriptor.defaultEnabled }
        if isSystemFeature || isSystemTweak || settingsGroup == .clean { return false }
        return switch self {
        case .captureEditor: false
        case .archivesInPlace: false
        case .archivesDefaultApp: false
        case .torrentsKeepSharing: false
        case .spacesOrder: false
        case .switcherQuitKey: false
        case .buildStats: false
        case .urlCleaner: false
        case .convertFiles: false
        case .mediaTools: false
        case .commandRunner: false
        case .downloads: false
        case .downloadsAria2: false
        case .distill: false
        case .distillTimestamps: false
        case .distillConvert: false
        case .machBlockedDialogAlert: false
        case .remoteScreen: false
        case .machMBPFans: false
        case .treadmillWalk: false
        default: true
        }
    }

    var isSystemFeature: Bool {
        if let descriptor { return descriptor.isSystemFeature }
        return settingsGroup == .systemTools || settingsGroup == .tools
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
    case screenRecording
    case microphone
    case calendars
    case bluetooth
}
