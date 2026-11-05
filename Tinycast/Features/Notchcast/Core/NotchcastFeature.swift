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
        switch self {
        case .tasksSync: [.tasks, .machLink]
        case .todoIsland: [.tasks]
        case .archives: []
        case .archivesInPlace: [.archives]
        case .archivesDefaultApp: [.archives]
        case .torrents: []
        case .torrentsUseIPhone: [.torrents]
        case .torrentsKeepSharing: [.torrents]
        case .island: []
        case .musicLastPlayer: [.island, .musicNowPlaying]
        case .spotifyConnect: [.island, .musicNowPlaying]
        default: needsIsland ? [.island] : []
        }
    }

    var settingsGroup: SettingsGroup {
        switch self {
        case .audioPriority: .systemTools
        case .cleaningMode: .tools
        case .appUpdates: .tools
        case .macUpdate: .tools
        case .tasks: .tasks
        case .tasksSync: .tasks
        case .todoIsland: .tasks
        case .githubSearch: .launcher
        case .clearNotifications: .launcher
        case .launcherAnswers: .launcher
        case .copyPath: .launcher
        case .smallCommands: .launcher
        case .aiUsage: .activities
        case .aiUsageOtherMac: .activities
        case .machLink: .system
        case .commandRunner: .launcher
        case .mediaTools: .activities
        case .convertFiles: .activities
        case .urlCleaner: .system
        case .musicNowPlaying: .music
        case .musicLastPlayer: .music
        case .musicBlockAppleMusic: .music
        case .spotifyConnect: .music
        case .microphoneMute: .music
        case .inUseMarks: .music
        case .buildStats: .buildStats
        case .agentMCPServer: .captureAndDictation
        case .agentChatTools: .captureAndDictation
        case .island: .island
        case .islandExternalDisplays: .islandOptions
        case .islandFullScreen: .islandOptions
        case .islandHoverOpen: .islandOptions
        case .islandStatusMessages: .islandOptions
        case .islandLiveActivities: .islandOptions
        case .launcherFromIsland: .launcher
        case .colorPicker: .captureAndDictation
        case .screenText: .captureAndDictation
        case .scrollingCapture: .captureAndDictation
        case .screenshot: .captureAndDictation
        case .launcherNumberKeys: .launcher
        case .launcherAliasSpace: .launcher
        case .machBlockedDialogAlert: .system
        case .remoteScreen: .system
        case .machMBPFans: .system
        case .dictationIslandHUD: .activities
        case .dictationCleanup: .captureAndDictation
        case .dictationEnglish: .captureAndDictation
        case .dictationHistory: .captureAndDictation
        case .captureTrimmer: .captureAndDictation
        case .captureEditor: .captureAndDictation
        case .agentAnswer: .captureAndDictation
        case .voiceAsk: .captureAndDictation
        case .recording: .captureAndDictation
        case .globeDictation: .captureAndDictation
        case .systemMonitor: .systemTools
        case .fanControl: .systemTools
        case .accessoryBatteries: .systemTools
        case .accessoryNotices: .system
        case .monitorAlerts: .systemTools
        case .lowDiskWarning: .system
        case .systemNotices: .system
        case .volumeLevels: .system
        case .displayBrightness: .system
        case .quitProtection: .system
        case .batteryChargeLimit: .systemTools
        case .batterySailing: .systemTools
        case .batteryHeatProtection: .systemTools
        case .batteryCalibration: .systemTools
        case .keepAwake: .systemTools
        case .lidClosedAwake: .systemTools
        case .linkQuickFixes: .systemTools
        case .backupRunNow: .system
        case .backupBrowseRestore: .system
        case .quickLookSpace: .launcher
        case .markdownFiles: .system
        case .plainTextFiles: .system
        case .editorSpellChecking: .system
        case .liveTimers: .activities
        case .dayCalendar: .activities
        case .dayWeather: .activities
        case .agentSessions: .activities
        case .openBotAgents: .activities
        case .agentThreads: .activities
        case .agentIsland: .activities
        case .fleetPanel: .activities
        case .waitingAlerts: .activities
        case .agentPricing: .agentPricing
        case .dayMarkets: .activities
        case .cleanJunk: .clean
        case .cleanHistory: .clean
        case .cleanAIData: .clean
        case .cleanDisk: .clean
        case .cleanPurge: .clean
        case .cleanOptimize: .clean
        case .cleanSystem: .clean
        case .settingsBackup: .system
        case .showDesktop: .system
        case .spacesOrder: .system
        case .hideCommandM: .system
        case .middleClick: .system
        case .greenMaximize: .system
        case .machineSetupProfile: .system
        case .agentConfirmation: .islandOptions
        case .eventReminder: .activities
        case .switcherQuitKey: .launcher
        case .agentActions: .system
        case .agentCLI: .system
        case .treadmillWalk: .activities
        case .treadmillHistory: .activities
        case .katana: .system
        case .appearance: .appearance
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
        case .machRemote: .system
        case .backupStatus: .system
        case .linkHealth: .system
        case .shelfBetweenMacs: .activities
        case .sendFiles: .system
        case .updateRemote: .system
        case .archives: .archives
        case .archivesInPlace: .archives
        case .archivesDefaultApp: .archives
        case .torrents: .torrents
        case .torrentsUseIPhone: .torrents
        case .torrentsKeepSharing: .torrents
        case .pastePlain: .clipboard
        case .finderCutPaste: .finder
        case .finderRename: .finder
        case .pasteImage: .clipboard
        }
    }

    var title: String {
        switch self {
        case .audioPriority: String(localized: "Audio device priority", table: "Notchcast")
        case .cleaningMode: String(localized: "Cleaning mode", table: "Notchcast")
        case .appUpdates: String(localized: "App updates", table: "Notchcast")
        case .macUpdate: String(localized: "Update this Mac", table: "Notchcast")
        case .tasks: String(localized: "Tasks", table: "Notchcast")
        case .tasksSync: String(localized: "Sync tasks between Macs", table: "Notchcast")
        case .todoIsland: String(localized: "Task island feed", table: "Notchcast")
        case .githubSearch: String(localized: "GitHub Search", table: "Notchcast")
        case .clearNotifications: String(localized: "Clear Notifications", table: "Notchcast")
        case .launcherAnswers: String(localized: "Currency Answers", table: "Notchcast")
        case .copyPath: String(localized: "Copy Path")
        case .smallCommands: String(localized: "Small Commands", table: "Notchcast")
        case .aiUsage: String(localized: "AI Usage", table: "Notchcast")
        case .aiUsageOtherMac: String(localized: "Other Mac AI Usage", table: "Notchcast")
        case .machLink: String(localized: "Mac Link", table: "Notchcast")
        case .commandRunner: String(localized: "Command Runner", table: "Notchcast")
        case .mediaTools: String(localized: "Media Tools", table: "Notchcast")
        case .convertFiles: String(localized: "Convert Files", table: "Notchcast")
        case .urlCleaner: String(localized: "URL cleaner", table: "Notchcast")
        case .musicNowPlaying: String(localized: "Show what is playing", table: "Notchcast")
        case .musicLastPlayer: String(localized: "Resume last player", table: "Notchcast")
        case .musicBlockAppleMusic: String(localized: "Stop Apple Music opening on media keys", table: "Notchcast")
        case .spotifyConnect: String(localized: "Spotify Connect speaker", table: "Notchcast")
        case .microphoneMute: String(localized: "Microphone mute", table: "Notchcast")
        case .inUseMarks: String(localized: "In-use marks", table: "Notchcast")
        case .buildStats: String(localized: "Build statistics", table: "Notchcast")
        case .agentMCPServer: String(localized: "Agent MCP Server", table: "Notchcast")
        case .agentChatTools: String(localized: "AI Chat Tools", table: "Notchcast")
        case .island: String(localized: "Island", table: "Notchcast")
        case .islandExternalDisplays: String(localized: "External Displays", table: "Notchcast")
        case .islandFullScreen: String(localized: "Full-Screen Apps", table: "Notchcast")
        case .islandHoverOpen: String(localized: "Open on Hover", table: "Notchcast")
        case .islandStatusMessages: String(localized: "Status Messages", table: "Notchcast")
        case .islandLiveActivities: String(localized: "Live Activities", table: "Notchcast")
        case .launcherFromIsland: String(localized: "Launcher from Island", table: "Notchcast")
        case .launcherNumberKeys: String(localized: "Launcher Number Keys", table: "Notchcast")
        case .launcherAliasSpace: String(localized: "Alias and Space", table: "Notchcast")
        case .systemMonitor: String(localized: "System Monitor", table: "Notchcast")
        case .monitorAlerts: String(localized: "Monitor Alerts", table: "Notchcast")
        case .fanControl: String(localized: "Fan Control", table: "Notchcast")
        case .accessoryBatteries: String(localized: "Accessory batteries", table: "Notchcast")
        case .accessoryNotices: String(localized: "Accessory notices", table: "Notchcast")
        case .lowDiskWarning: String(localized: "Low Disk Warning", table: "Notchcast")
        case .systemNotices: String(localized: "System Notices", table: "Notchcast")
        case .volumeLevels: String(localized: "Volume in Island", table: "Notchcast")
        case .displayBrightness: String(localized: "Display Brightness", table: "Notchcast")
        case .quitProtection: String(localized: "Quit Protection", table: "Notchcast")
        case .liveTimers: String(localized: "Timers", table: "Notchcast")
        case .dayCalendar: String(localized: "Calendar")
        case .dayWeather: String(localized: "Weather")
        case .agentActions: String(localized: "Agent access", table: "Notchcast")
        case .agentCLI: String(localized: "Command line tool", table: "Notchcast")
        case .treadmillWalk: String(localized: "Walking Pad", table: "Notchcast")
        case .treadmillHistory: String(localized: "Walk History", table: "Notchcast")
        case .katana: String(localized: "Katana", table: "Notchcast")
        case .appearance: String(localized: "Custom appearance", table: "Notchcast")
        case .agentSessions: String(localized: "Agent Session Logs", table: "Notchcast")
        case .openBotAgents: String(localized: "OpenBot Agents", table: "Notchcast")
        case .agentThreads: String(localized: "Agent Threads", table: "Notchcast")
        case .agentIsland: String(localized: "Agent Island", table: "Notchcast")
        case .fleetPanel: String(localized: "Fleet Panel", table: "Notchcast")
        case .waitingAlerts: String(localized: "Waiting-for-you alerts", table: "Notchcast")
        case .agentPricing: String(localized: "Agent API Value", table: "Notchcast")
        case .pastePlain: String(localized: "Paste Plain Text", table: "Notchcast")
        case .finderCutPaste: String(localized: "Finder Cut and Paste", table: "Notchcast")
        case .finderRename: String(localized: "Finder Rename", table: "Notchcast")
        case .pasteImage: String(localized: "Paste Image in Finder", table: "Notchcast")
        case .dayMarkets: String(localized: "Markets", table: "Notchcast")
        case .colorPicker: String(localized: "Color Picker", table: "Notchcast")
        case .screenshot: String(localized: "Screenshots", table: "Notchcast")
        case .screenText: String(localized: "Capture Text", table: "Notchcast")
        case .scrollingCapture: String(localized: "Scrolling Capture", table: "Notchcast")
        case .greenMaximize: String(localized: "Green Button Maximizes", table: "Notchcast")
        case .middleClick: String(localized: "Trackpad Middle Click", table: "Notchcast")
        case .hideCommandM: String(localized: "Hide with ⌘M", table: "Notchcast")
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
        case .machRemote: String(localized: "Remote Mac", table: "Notchcast")
        case .backupStatus: String(localized: "Backup Status", table: "Notchcast")
        case .linkHealth: String(localized: "Link Health", table: "Notchcast")
        case .shelfBetweenMacs: String(localized: "Shelf between Macs", table: "Notchcast")
        case .sendFiles: String(localized: "Send to Remote Mac", table: "Notchcast")
        case .updateRemote: String(localized: "Update Remote Mac", table: "Notchcast")
        case .archives: String(localized: "Archives")
        case .archivesInPlace: String(localized: "Extract in place", table: "Notchcast")
        case .archivesDefaultApp: String(localized: "Open archives with Notchcast", table: "Notchcast")
        case .torrents: String(localized: "Torrents", table: "Notchcast")
        case .torrentsUseIPhone: String(localized: "Use a plugged-in iPhone for big downloads", table: "Notchcast")
        case .torrentsKeepSharing: String(localized: "Keep sharing until ratio 1.0", table: "Notchcast")
        case .dictationIslandHUD: String(localized: "Dictation in Island", table: "Notchcast")
        case .dictationCleanup: String(localized: "AI cleanup", table: "Notchcast")
        case .dictationEnglish: String(localized: "Dictate in English", table: "Notchcast")
        case .dictationHistory: String(localized: "Keep dictation history", table: "Notchcast")
        case .captureTrimmer: String(localized: "Recording Trimmer", table: "Notchcast")
        case .captureEditor: String(localized: "Capture Editor", table: "Notchcast")
        case .agentAnswer: String(localized: "Agent Answers", table: "Notchcast")
        case .voiceAsk: String(localized: "Voice Ask", table: "Notchcast")
        case .recording: String(localized: "Screen Recording", table: "Notchcast")
        case .globeDictation: String(localized: "Globe Dictation", table: "Notchcast")
        case .batteryChargeLimit: String(localized: "Charge Limit", table: "Notchcast")
        case .batterySailing: String(localized: "Battery Sailing", table: "Notchcast")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection", table: "Notchcast")
        case .batteryCalibration: String(localized: "Battery Calibration", table: "Notchcast")
        case .keepAwake: String(localized: "Keep Awake", table: "Notchcast")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed", table: "Notchcast")
        case .cleanJunk: String(localized: "Junk", table: "Notchcast")
        case .cleanHistory: String(localized: "Clean history", table: "Notchcast")
        case .cleanAIData: String(localized: "AI data", table: "Notchcast")
        case .cleanDisk: String(localized: "Disk analyzer", table: "Notchcast")
        case .cleanPurge: String(localized: "Project purge", table: "Notchcast")
        case .cleanOptimize: String(localized: "Optimize", table: "Notchcast")
        case .cleanSystem: String(localized: "System root", table: "Notchcast")
        case .settingsBackup: String(localized: "Settings Backup", table: "Notchcast")
        case .machineSetupProfile: String(localized: "Machine Setup Profile", table: "Notchcast")
        case .agentConfirmation: String(localized: "Agent Confirmation", table: "Notchcast")
        case .eventReminder: String(localized: "Event Reminders", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Switcher Quit Key", table: "Notchcast")
        case .linkQuickFixes: String(localized: "Link Quick Fixes", table: "Notchcast")
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
        }
    }

    var subtitle: String {
        switch self {
        case .audioPriority: String(localized: "Choose devices automatically when they connect or disconnect.", table: "Notchcast")
        case .cleaningMode: String(localized: "Press Escape five times to exit; ends after 300 seconds.", table: "Notchcast")
        case .appUpdates: String(localized: "Check installed apps for updates on demand.", table: "Notchcast")
        case .macUpdate: String(localized: "Run maintenance only after confirmation.", table: "Notchcast")
        case .tasks: String(localized: "Keep tasks on this Mac.", table: "Notchcast")
        case .tasksSync: String(localized: "Exchange tasks with your paired Mac over Mac Link.", table: "Notchcast")
        case .todoIsland: String(localized: "Prepare task snapshots for the island.", table: "Notchcast")
        case .githubSearch: String(localized: "Search GitHub repositories and starred projects.", table: "Notchcast")
        case .clearNotifications: String(localized: "Clear notifications from Notification Center. Requires English system language.", table: "Notchcast")
        case .launcherAnswers: String(localized: "Currency answers using rates from NBP.", table: "Notchcast")
        case .copyPath: String(localized: "Copy the frontmost document path or browser link.", table: "Notchcast")
        case .smallCommands: String(localized: "Passwords, short links, noise control and AirDrop. Noise control requires English system language.", table: "Notchcast")
        case .aiUsage: String(localized: "Read local AI usage on demand.", table: "Notchcast")
        case .aiUsageOtherMac: String(localized: "Include usage from the other Mac.", table: "Notchcast")
        case .machLink: String(localized: "Connect to a paired Mac on the local network.", table: "Notchcast")
        case .commandRunner: String(localized: "Run commands from a host profile.", table: "Notchcast")
        case .mediaTools: String(localized: "Compress media, make GIFs and extract text locally.", table: "Notchcast")
        case .convertFiles: String(localized: "Convert local files beside the originals.", table: "Notchcast")
        case .urlCleaner: String(localized: "Remove tracking parameters from copied links.", table: "Notchcast")
        case .musicNowPlaying: String(localized: "Show track information in the island.", table: "Notchcast")
        case .musicLastPlayer: String(localized: "Send playback controls to the last active player.", table: "Notchcast")
        case .musicBlockAppleMusic: String(localized: "Prevent media keys from launching Apple Music.", table: "Notchcast")
        case .spotifyConnect: String(localized: "Use this Mac as a Spotify playback device.", table: "Notchcast")
        case .microphoneMute: String(localized: "Press F5 to mute or unmute microphones.", table: "Notchcast")
        case .inUseMarks: String(localized: "Show when the camera or microphone is in use.", table: "Notchcast")
        case .buildStats: String(localized: "Read a local build snapshot.", table: "Notchcast")
        case .agentMCPServer: String(localized: "Nothing is exposed until the CLI is available.", table: "Notchcast")
        case .agentChatTools: String(localized: "Add Notchcast tools to AI chat.", table: "Notchcast")
        case .dictationEnglish: String(localized: "Use English for dictation.", table: "Notchcast")
        case .island: String(localized: "Show the island at the top of the screen.", table: "Notchcast")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.", table: "Notchcast")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.", table: "Notchcast")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.", table: "Notchcast")
        case .islandStatusMessages: String(localized: "Show status messages in the island.", table: "Notchcast")
        case .islandLiveActivities: String(localized: "Show live activities in the island.", table: "Notchcast")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.", table: "Notchcast")
        case .launcherNumberKeys: String(localized: "Open the first nine search results with Command-1 through Command-9.", table: "Notchcast")
        case .launcherAliasSpace: String(localized: "Press Space after an exact alias to open its command.", table: "Notchcast")
        case .systemMonitor: String(localized: "Monitor system performance.", table: "Notchcast")
        case .monitorAlerts: String(localized: "Sample your Mac in the background while alerts are on.", table: "Notchcast")
        case .fanControl: String(localized: "Control fans with the privileged helper.", table: "Notchcast")
        case .accessoryBatteries: String(localized: "Show connected accessory battery levels.", table: "Notchcast")
        case .accessoryNotices: String(localized: "Show accessory connections and low battery notices.", table: "Notchcast")
        case .lowDiskWarning: String(localized: "Warns below \(10)% or \(30) GB free.", table: "Notchcast")
        case .systemNotices: String(localized: "Wi-Fi, Tailscale and low battery notices in the island.", table: "Notchcast")
        case .volumeLevels: String(localized: "Replaces the macOS volume overlay.", table: "Notchcast")
        case .displayBrightness: String(localized: "Brightness keys control every display, external ones too.", table: "Notchcast")
        case .quitProtection: String(localized: "Stops an app from quitting on a single slip.", table: "Notchcast")
        case .liveTimers: String(localized: "Countdowns and alarms in the island.", table: "Notchcast")
        case .dayCalendar: String(localized: "Calendar events on the Day page.", table: "Notchcast")
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.", table: "Notchcast")
        case .agentActions: String(localized: "Expose actions and read-only state to local agents.", table: "Notchcast")
        case .agentCLI: String(localized: "Accept local commands over a private Unix socket.", table: "Notchcast")
        case .treadmillWalk: String(localized: "Control a Bluetooth walking pad from the launcher.", table: "Notchcast")
        case .treadmillHistory: String(localized: "Keep walk totals, daily goals and lubrication reminders.", table: "Notchcast")
        case .katana: String(localized: "Switch Katana amp channels from the launcher.", table: "Notchcast")
        case .appearance: String(localized: "Themes and surface styles for the launcher, dialogs and HUDs.", table: "Notchcast")
        case .agentSessions: String(localized: "Read local agent session metadata and token usage on demand.", table: "Notchcast")
        case .openBotAgents: String(localized: "Read waiting items from local OpenBot agents.", table: "Notchcast")
        case .agentThreads: String(localized: "Read active and recently finished agent threads on this Mac.", table: "Notchcast")
        case .agentIsland: String(localized: "Summarize waiting and working agents.", table: "Notchcast")
        case .fleetPanel: String(localized: "Read T3 Code threads on both Macs on demand.", table: "Notchcast")
        case .waitingAlerts: String(localized: "Notify when an agent needs approval or an answer.", table: "Notchcast")
        case .agentPricing: String(localized: "Estimate API value from local agent token usage.", table: "Notchcast")
        case .pastePlain: String(localized: "Paste text without formatting from the launcher.", table: "Notchcast")
        case .finderCutPaste: String(localized: "Use ⌘X and ⌘V to move files in Finder.", table: "Notchcast")
        case .finderRename: String(localized: "Use Hyper+R to rename the selection in Finder.", table: "Notchcast")
        case .pasteImage: String(localized: "Command+V saves clipboard images as PNG files in Finder.", table: "Notchcast")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.", table: "Notchcast")
        case .colorPicker: String(localized: "Copy a color from anywhere on the screen.", table: "Notchcast")
        case .screenshot: String(localized: "Capture an area, window or display.", table: "Notchcast")
        case .screenText: String(localized: "Copy text from a selected screen area.", table: "Notchcast")
        case .scrollingCapture: String(localized: "Copy a scrolling area as one image.", table: "Notchcast")
        case .greenMaximize: String(localized: "Click the green button to maximize or restore; hold Option for macOS behavior.", table: "Notchcast")
        case .middleClick: String(localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.", table: "Notchcast")
        case .hideCommandM: String(localized: "Hide the front app instead of minimizing its window.", table: "Notchcast")
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
        case .machRemote: String(localized: "Connect to the remote Mac using SSH.", table: "Notchcast")
        case .backupStatus: String(localized: "Warns when backups fail or become stale.", table: "Notchcast")
        case .linkHealth: String(localized: "Notify when the paired Mac disconnects or reconnects.", table: "Notchcast")
        case .shelfBetweenMacs: String(localized: "Send small items to the paired Mac.", table: "Notchcast")
        case .sendFiles: String(localized: "Send selected files to the remote Mac.", table: "Notchcast")
        case .updateRemote: String(localized: "Run the update on the remote Mac.", table: "Notchcast")
        case .archives: String(localized: "Extract opened archives beside the original file.", table: "Notchcast")
        case .archivesInPlace: String(localized: "The archive shrinks while extracting.", table: "Notchcast")
        case .archivesDefaultApp: String(localized: "Use Notchcast instead of Archive Utility to open archives.", table: "Notchcast")
        case .torrents: String(localized: "Download magnet links and torrent files to Downloads.", table: "Notchcast")
        case .torrentsUseIPhone: String(localized: "Use Wi-Fi and iPhone USB Personal Hotspot together.", table: "Notchcast")
        case .torrentsKeepSharing: String(localized: "Upload as much as you download before stopping.", table: "Notchcast")
        case .dictationIslandHUD: String(localized: "Show dictation status in the island.", table: "Notchcast")
        case .dictationCleanup: String(localized: "Clean up final dictation transcripts.", table: "Notchcast")
        case .dictationHistory: String(localized: "Save transcripts for later review.", table: "Notchcast")
        case .captureTrimmer: String(localized: "Trim recordings and export MP4 or GIF files.", table: "Notchcast")
        case .captureEditor: String(localized: "Mark up a capture and copy it.", table: "Notchcast")
        case .agentAnswer: String(localized: "Reply to waiting agents.", table: "Notchcast")
        case .voiceAsk: String(localized: "Voice Ask destination", table: "Notchcast")
        case .recording: String(localized: "Record an area, window or display with system audio.", table: "Notchcast")
        case .globeDictation: String(localized: "Tap Globe to start or finish dictation, or hold it to talk.", table: "Notchcast")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.", table: "Notchcast")
        case .batterySailing: String(localized: "Use battery power above the charge limit.", table: "Notchcast")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.", table: "Notchcast")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.", table: "Notchcast")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.", table: "Notchcast")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.", table: "Notchcast")
        case .cleanJunk: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .cleanHistory: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .cleanAIData: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .cleanDisk: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .cleanPurge: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .cleanOptimize: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .cleanSystem: String(localized: "Runs only when you click an action.", table: "Notchcast")
        case .settingsBackup: String(localized: "Back up safe Notchcast preferences daily.", table: "Notchcast")
        case .machineSetupProfile: String(localized: "Plan portable setup imports and exports.", table: "Notchcast")
        case .agentConfirmation: String(localized: "Ask before allowing agent requests.", table: "Notchcast")
        case .eventReminder: String(localized: "Show calendar alerts in the island.", table: "Notchcast")
        case .switcherQuitKey: String(localized: "Press Q in an empty window search to quit the selected app.", table: "Notchcast")
        case .linkQuickFixes: String(localized: "Offer manual fixes for connection problems.", table: "Notchcast")
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
        }
    }

    /// What the feature cannot work without; Settings lists these while the feature is on.
    var requiredGrants: [NotchcastGrant] {
        switch self {
        case .accessoryNotices: [.bluetooth]
        case .cleaningMode: [.accessibility]
        case .screenText: [.screenRecording]
        case .scrollingCapture: [.screenRecording]
        case .dictationEnglish: [.accessibility]
        case .clearNotifications: [.accessibility]
        case .copyPath: [.accessibility]
        case .smallCommands: [.accessibility]
        case .screenshot: [.screenRecording]
        case .musicNowPlaying: []
        case .musicLastPlayer: [.accessibility]
        case .musicBlockAppleMusic: [.accessibility]
        case .spotifyConnect: []
        case .microphoneMute: [.accessibility]
        case .inUseMarks: []
        case .showDesktop: [.accessibility]
        case .hideCommandM: [.accessibility]
        case .middleClick: [.accessibility]
        case .greenMaximize: [.accessibility]
        case .switcherQuitKey: [.accessibility]
        case .voiceAsk: [.accessibility, .microphone]
        case .recording: [.screenRecording]
        case .globeDictation: [.accessibility, .microphone]
        case .dayCalendar: [.calendars]
        case .eventReminder: [.calendars]
        case .volumeLevels: [.accessibility]
        case .displayBrightness: [.accessibility]
        case .quitProtection: [.accessibility]
        case .notificationCleanup: [.accessibility]
        case .startupItems: []
        case .sudoTouchID: []
        case .killProcess: []
        case .macSetup: []
        case .aiFeaturesOff: []
        case .spotlightOff: []
        case .privacyChoices: []
        case .island: []
        case .islandExternalDisplays: []
        case .islandFullScreen: []
        case .islandHoverOpen: []
        case .islandStatusMessages: []
        case .islandLiveActivities: []
        case .launcherFromIsland: []
        case .lowDiskWarning: []
        case .systemNotices: []
        case .liveTimers: []
        case .dayWeather: []
        case .dayMarkets: []
        case .typingTweaks: []
        case .finderTweaks: []
        case .dockTweaks: []
        case .appleAppsTweaks: []
        case .iPhoneBackupTweaks: []
        case .systemMonitor: []
        case .monitorAlerts: []
        case .fanControl: []
        case .batteryChargeLimit: []
        case .batterySailing: []
        case .batteryHeatProtection: []
        case .batteryCalibration: []
        case .keepAwake: []
        case .lidClosedAwake: []
        case .pastePlain: [.accessibility]
        case .finderCutPaste: [.accessibility]
        case .finderRename: [.accessibility]
        case .pasteImage: [.accessibility]
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
        .captureEditor,
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
        if isSystemFeature || isSystemTweak || settingsGroup == .clean { return false }
        return switch self {
        case .island: false
        case .tasks: false
        case .tasksSync: false
        case .todoIsland: false
        case .githubSearch: false
        case .clearNotifications: false
        case .launcherAnswers: false
        case .copyPath: false
        case .smallCommands: false
        case .aiUsage: false
        case .aiUsageOtherMac: false
        case .machLink: false
        case .colorPicker: false
        case .screenText: false
        case .scrollingCapture: false
        case .screenshot: false
        case .buildStats: false
        case .agentPricing: false
        case .launcherNumberKeys: false
        case .launcherAliasSpace: false
        case .urlCleaner: false
        case .convertFiles: false
        case .mediaTools: false
        case .commandRunner: false
        case .settingsBackup: false
        case .showDesktop: false
        case .spacesOrder: false
        case .hideCommandM: false
        case .middleClick: false
        case .greenMaximize: false
        case .machineSetupProfile: false
        case .switcherQuitKey: false
        case .agentSessions: false
        case .openBotAgents: false
        case .agentThreads: false
        case .agentIsland: false
        case .fleetPanel: false
        case .waitingAlerts: false
        case .archives: false
        case .archivesInPlace: false
        case .archivesDefaultApp: false
        case .torrents: false
        case .torrentsUseIPhone: false
        case .torrentsKeepSharing: false
        case .dictationCleanup: false
        case .dictationEnglish: false
        case .dictationHistory: false
        case .captureTrimmer: false
        case .captureEditor: false
        case .agentAnswer: false
        case .voiceAsk: false
        case .recording: false
        case .globeDictation: false
        case .agentMCPServer: false
        case .agentChatTools: false
        case .displayBrightness: false
        case .quitProtection: false
        case .agentActions: false
        case .agentCLI: false
        case .treadmillWalk: false
        case .treadmillHistory: false
        case .appearance: false
        case .downloads: false
        case .downloadsAria2: false
        case .distill: false
        case .distillTimestamps: false
        case .distillConvert: false
        case .remoteScreen: false
        case .machMBPFans: false
        case .machRemote: false
        case .backupStatus: false
        case .linkHealth: false
        case .shelfBetweenMacs: false
        case .sendFiles: false
        case .updateRemote: false
        case .backupRunNow: false
        case .backupBrowseRestore: false
        case .quickLookSpace: false
        case .markdownFiles: false
        case .plainTextFiles: false
        case .editorSpellChecking: false
        case .pastePlain: false
        case .finderCutPaste: false
        case .finderRename: false
        case .pasteImage: false
        default: true
        }
    }

    var isSystemTweak: Bool {
        switch self {
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
    var isLauncherKeysFeature: Bool { self == .launcherNumberKeys || self == .launcherAliasSpace }

    var defaultEnabled: Bool {
        if isSystemFeature || isSystemTweak || settingsGroup == .clean || isLauncherKeysFeature { return false }
        return switch self {
        case .tasks: false
        case .tasksSync: false
        case .todoIsland: false
        case .accessoryNotices: false
        case .spotifyConnect: false
        case .captureEditor: false
        case .archivesInPlace: false
        case .archivesDefaultApp: false
        case .torrentsKeepSharing: false
        case .spacesOrder: false
        case .switcherQuitKey: false
        case .buildStats: false
        case .voiceAsk: false
        case .agentMCPServer: false
        case .dictationEnglish: false
        case .agentAnswer: false
        case .dictationCleanup: false
        case .pastePlain: false
        case .githubSearch: false
        case .clearNotifications: false
        case .launcherAnswers: false
        case .copyPath: false
        case .smallCommands: false
        case .aiUsage: false
        case .aiUsageOtherMac: false
        case .machLink: false
        case .urlCleaner: false
        case .convertFiles: false
        case .mediaTools: false
        case .commandRunner: false
        case .downloads: false
        case .downloadsAria2: false
        case .distill: false
        case .distillTimestamps: false
        case .distillConvert: false
        case .machRemote: false
        case .backupStatus: false
        case .linkHealth: false
        case .shelfBetweenMacs: false
        case .sendFiles: false
        case .updateRemote: false
        case .machBlockedDialogAlert: false
        case .remoteScreen: false
        case .machMBPFans: false
        case .agentSessions: false
        case .openBotAgents: false
        case .agentThreads: false
        case .agentIsland: false
        case .fleetPanel: false
        case .waitingAlerts: false
        case .agentPricing: false
        case .treadmillWalk: false
        default: true
        }
    }

    var isSystemFeature: Bool {
        switch self {
        case .katana: true
        default: settingsGroup == .systemTools || settingsGroup == .tools
        }
    }
}

enum NotchcastGrant: CaseIterable, Sendable {
    case accessibility
    case screenRecording
    case microphone
    case calendars
    case bluetooth
}
