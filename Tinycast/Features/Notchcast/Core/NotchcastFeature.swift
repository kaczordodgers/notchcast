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
        case .editorSpellChecking: .system
        case .treadmillWalk: .activities
        case .treadmillHistory: .activities
        default: preconditionFailure("\(self) has neither a descriptor nor a settingsGroup arm")
        }
    }

    var title: String {
        if let descriptor { return descriptor.title }
        return switch self {
        case .treadmillWalk: String(localized: "Walking Pad", table: "Notchcast")
        case .treadmillHistory: String(localized: "Walk History", table: "Notchcast")
        case .editorSpellChecking: String(localized: "Editor Spell Checking", table: "Notchcast")
        default: preconditionFailure("\(self) has neither a descriptor nor a title arm")
        }
    }

    var subtitle: String {
        if let descriptor { return descriptor.subtitle }
        return switch self {
        case .treadmillWalk: String(localized: "Control a Bluetooth walking pad from the launcher.", table: "Notchcast")
        case .treadmillHistory: String(localized: "Keep walk totals, daily goals and lubrication reminders.", table: "Notchcast")
        case .editorSpellChecking: String(localized: "Check spelling in the editor.", table: "Notchcast")
        default: preconditionFailure("\(self) has neither a descriptor nor a subtitle arm")
        }
    }

    /// Whether a settings backup carries the switch; a switch that grants a capability stays out.
    var backedUp: Bool {
        if let descriptor { return descriptor.backedUp }
        return switch self {
        case .treadmillWalk: false
        case .treadmillHistory: false
        case .editorSpellChecking: true
        default: preconditionFailure("\(self) has neither a descriptor nor a backedUp arm")
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        descriptor?.requiredGrants ?? []
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
        .launcherAnswers,
        .remoteScreen,
        .machMBPFans,
        .machineSetupProfile,
        .commandRunner,
    ]

    static var systemToolsSettingsFeatures: [Self] {
        allCases.filter { $0.usesSystemToolsHelper && $0.isWired }
    }

    var usesSystemToolsHelper: Bool {
        descriptor?.usesSystemToolsHelper ?? false
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
        case .treadmillWalk: false
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
