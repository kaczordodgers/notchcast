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
    case musicSharpCovers
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
        descriptor?.dependencies ?? []
    }

    var settingsGroup: SettingsGroup {
        if let descriptor { return descriptor.group }
        return switch self {
        case .colorPicker: .captureAndDictation
        case .scrollingCapture: .captureAndDictation
        case .screenshot: .captureAndDictation
        case .captureTrimmer: .captureAndDictation
        case .captureEditor: .captureAndDictation
        case .recording: .captureAndDictation
        case .editorSpellChecking: .system
        case .switcherQuitKey: .launcher
        case .treadmillWalk: .activities
        case .treadmillHistory: .activities
        case .githubSearch: .launcher
        case .clearNotifications: .launcher
        case .launcherAnswers: .launcher
        case .copyPath: .launcher
        case .smallCommands: .launcher
        case .launcherNumberKeys: .launcher
        case .launcherAliasSpace: .launcher
        default: preconditionFailure("\(self) has neither a descriptor nor a settingsGroup arm")
        }
    }

    var title: String {
        if let descriptor { return descriptor.title }
        return switch self {
        case .treadmillWalk: String(localized: "Walking Pad", table: "Notchcast")
        case .treadmillHistory: String(localized: "Walk History", table: "Notchcast")
        case .colorPicker: String(localized: "Color Picker", table: "Notchcast")
        case .screenshot: String(localized: "Screenshots", table: "Notchcast")
        case .scrollingCapture: String(localized: "Scrolling Capture", table: "Notchcast")
        case .captureTrimmer: String(localized: "Recording Trimmer", table: "Notchcast")
        case .captureEditor: String(localized: "Capture Editor", table: "Notchcast")
        case .recording: String(localized: "Screen Recording", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Switcher Quit Key", table: "Notchcast")
        case .editorSpellChecking: String(localized: "Editor Spell Checking", table: "Notchcast")
        case .githubSearch: String(localized: "GitHub Search", table: "Notchcast")
        case .clearNotifications: String(localized: "Clear Notifications", table: "Notchcast")
        case .launcherAnswers: String(localized: "Currency Answers", table: "Notchcast")
        case .copyPath: String(localized: "Copy Path")
        case .smallCommands: String(localized: "Small Commands", table: "Notchcast")
        case .launcherNumberKeys: String(localized: "Launcher Number Keys", table: "Notchcast")
        case .launcherAliasSpace: String(localized: "Alias and Space", table: "Notchcast")
        default: preconditionFailure("\(self) has neither a descriptor nor a title arm")
        }
    }

    var subtitle: String {
        if let descriptor { return descriptor.subtitle }
        return switch self {
        case .treadmillWalk: String(localized: "Control a Bluetooth walking pad from the launcher.", table: "Notchcast")
        case .treadmillHistory: String(localized: "Keep walk totals, daily goals and lubrication reminders.", table: "Notchcast")
        case .colorPicker: String(localized: "Copy a color from anywhere on the screen.", table: "Notchcast")
        case .screenshot: String(localized: "Capture an area, window or display.", table: "Notchcast")
        case .scrollingCapture: String(localized: "Copy a scrolling area as one image.", table: "Notchcast")
        case .captureTrimmer: String(localized: "Trim recordings and export MP4 or GIF files.", table: "Notchcast")
        case .captureEditor: String(localized: "Mark up a capture and copy it.", table: "Notchcast")
        case .recording: String(localized: "Record an area, window or display with system audio.", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Press Q in an empty window search to quit the selected app.", table: "Notchcast")
        case .editorSpellChecking: String(localized: "Check spelling in the editor.", table: "Notchcast")
        case .githubSearch: String(localized: "Search GitHub repositories and starred projects.", table: "Notchcast")
        case .clearNotifications: String(localized: "Clear notifications from Notification Center. Requires English system language.", table: "Notchcast")
        case .launcherAnswers: String(localized: "Currency answers using rates from NBP.", table: "Notchcast")
        case .copyPath: String(localized: "Copy the frontmost document path or browser link.", table: "Notchcast")
        case .smallCommands: String(localized: "Passwords, short links, noise control and AirDrop. Noise control requires English system language.", table: "Notchcast")
        case .launcherNumberKeys: String(localized: "Open the first nine search results with Command-1 through Command-9.", table: "Notchcast")
        case .launcherAliasSpace: String(localized: "Press Space after an exact alias to open its command.", table: "Notchcast")
        default: preconditionFailure("\(self) has neither a descriptor nor a subtitle arm")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        if let descriptor { return descriptor.requiredGrants }
        return switch self {
        case .scrollingCapture: [.screenRecording]
        case .screenshot: [.screenRecording]
        case .switcherQuitKey: [.accessibility]
        case .recording: [.screenRecording]
        case .clearNotifications: [.accessibility]
        case .copyPath: [.accessibility]
        case .smallCommands: [.accessibility]
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
        dependencies.contains(.island)
    }

    var isSystemTweak: Bool {
        descriptor?.isSystemTweak ?? false
    }

    var defaultEnabled: Bool {
        if let descriptor { return descriptor.defaultEnabled }
        return switch self {
        case .captureEditor: false
        case .switcherQuitKey: false
        case .treadmillWalk: false
        case .githubSearch: false
        case .clearNotifications: false
        case .launcherAnswers: false
        case .copyPath: false
        case .smallCommands: false
        case .launcherNumberKeys: false
        case .launcherAliasSpace: false
        default: true
        }
    }

    var isSystemFeature: Bool {
        descriptor?.isSystemFeature ?? false
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
    case screenRecording
    case microphone
    case calendars
    case bluetooth
}
