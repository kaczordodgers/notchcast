import Foundation

enum NotchcastFeature: String, CaseIterable, Sendable {
    case tasks
    case tasksSync
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
        case .audioPriority: String(localized: "Audio device priority")
        case .cleaningMode: String(localized: "Cleaning mode")
        case .appUpdates: String(localized: "App updates")
        case .macUpdate: String(localized: "Update this Mac")
        case .tasks: String(localized: "Tasks")
        case .tasksSync: String(localized: "Sync tasks between Macs")
        case .githubSearch: String(localized: "GitHub Search")
        case .clearNotifications: String(localized: "Clear Notifications")
        case .launcherAnswers: String(localized: "Currency Answers")
        case .copyPath: String(localized: "Copy Path")
        case .smallCommands: String(localized: "Small Commands")
        case .aiUsage: String(localized: "AI Usage")
        case .aiUsageOtherMac: String(localized: "Other Mac AI Usage")
        case .machLink: String(localized: "Mac Link")
        case .commandRunner: String(localized: "Command Runner")
        case .mediaTools: String(localized: "Media Tools")
        case .convertFiles: String(localized: "Convert Files")
        case .urlCleaner: String(localized: "URL cleaner")
        case .musicNowPlaying: String(localized: "Show what is playing")
        case .musicLastPlayer: String(localized: "Resume last player")
        case .musicBlockAppleMusic: String(localized: "Stop Apple Music opening on media keys")
        case .spotifyConnect: String(localized: "Spotify Connect speaker")
        case .microphoneMute: String(localized: "Microphone mute")
        case .inUseMarks: String(localized: "In-use marks")
        case .buildStats: String(localized: "Build statistics")
        case .agentMCPServer: String(localized: "Agent MCP Server")
        case .agentChatTools: String(localized: "AI Chat Tools")
        case .island: String(localized: "Island")
        case .islandExternalDisplays: String(localized: "External Displays")
        case .islandFullScreen: String(localized: "Full-Screen Apps")
        case .islandHoverOpen: String(localized: "Open on Hover")
        case .islandStatusMessages: String(localized: "Status Messages")
        case .islandLiveActivities: String(localized: "Live Activities")
        case .launcherFromIsland: String(localized: "Launcher from Island")
        case .launcherNumberKeys: String(localized: "Launcher Number Keys")
        case .launcherAliasSpace: String(localized: "Alias and Space")
        case .systemMonitor: String(localized: "System Monitor")
        case .monitorAlerts: String(localized: "Monitor Alerts")
        case .fanControl: String(localized: "Fan Control")
        case .accessoryBatteries: String(localized: "Accessory batteries")
        case .accessoryNotices: String(localized: "Accessory notices")
        case .lowDiskWarning: String(localized: "Low Disk Warning")
        case .systemNotices: String(localized: "System Notices")
        case .volumeLevels: String(localized: "Volume in Island")
        case .displayBrightness: String(localized: "Display Brightness")
        case .quitProtection: String(localized: "Quit Protection")
        case .liveTimers: String(localized: "Timers")
        case .dayCalendar: String(localized: "Calendar")
        case .dayWeather: String(localized: "Weather")
        case .agentActions: String(localized: "Agent access")
        case .agentCLI: String(localized: "Command line tool")
        case .treadmillWalk: String(localized: "Walking Pad")
        case .treadmillHistory: String(localized: "Walk History")
        case .katana: String(localized: "Katana")
        case .appearance: String(localized: "Custom appearance")
        case .agentSessions: String(localized: "Agent Session Logs")
        case .openBotAgents: String(localized: "OpenBot Agents")
        case .agentThreads: String(localized: "Agent Threads")
        case .waitingAlerts: String(localized: "Waiting-for-you alerts")
        case .agentPricing: String(localized: "Agent API Value")
        case .pastePlain: String(localized: "Paste Plain Text")
        case .finderCutPaste: String(localized: "Finder Cut and Paste")
        case .finderRename: String(localized: "Finder Rename")
        case .pasteImage: String(localized: "Paste Image in Finder")
        case .dayMarkets: String(localized: "Markets")
        case .colorPicker: String(localized: "Color Picker")
        case .screenshot: String(localized: "Screenshots")
        case .screenText: String(localized: "Capture Text")
        case .scrollingCapture: String(localized: "Scrolling Capture")
        case .greenMaximize: String(localized: "Green Button Maximizes")
        case .middleClick: String(localized: "Trackpad Middle Click")
        case .hideCommandM: String(localized: "Hide with ⌘M")
        case .spacesOrder: String(localized: "Keep Spaces in a fixed order")
        case .showDesktop: String(localized: "Show Desktop with F3")
        case .startupItems: String(localized: "Startup Items")
        case .notificationCleanup: String(localized: "Notification Cleanup")
        case .sudoTouchID: String(localized: "Touch ID for sudo")
        case .killProcess: String(localized: "Kill Process")
        case .macSetup: String(localized: "Mac Setup Presets")
        case .aiFeaturesOff: String(localized: "AI Features Off")
        case .spotlightOff: String(localized: "Spotlight Indexing Off")
        case .privacyChoices: String(localized: "Privacy Choices")
        case .typingTweaks: String(localized: "Typing")
        case .finderTweaks: String(localized: "Finder")
        case .dockTweaks: String(localized: "Dock and windows")
        case .appleAppsTweaks: String(localized: "Apple apps")
        case .iPhoneBackupTweaks: String(localized: "iPhone backup")
        case .machRemote: String(localized: "Remote Mac")
        case .backupStatus: String(localized: "Backup Status")
        case .linkHealth: String(localized: "Link Health")
        case .shelfBetweenMacs: String(localized: "Shelf between Macs")
        case .sendFiles: String(localized: "Send to Remote Mac")
        case .updateRemote: String(localized: "Update Remote Mac")
        case .archives: String(localized: "Archives")
        case .archivesInPlace: String(localized: "Extract in place")
        case .archivesDefaultApp: String(localized: "Open archives with Notchcast")
        case .torrents: String(localized: "Torrents")
        case .torrentsUseIPhone: String(localized: "Use a plugged-in iPhone for big downloads")
        case .torrentsKeepSharing: String(localized: "Keep sharing until ratio 1.0")
        case .dictationIslandHUD: String(localized: "Dictation in Island")
        case .dictationCleanup: String(localized: "AI cleanup")
        case .dictationEnglish: String(localized: "Dictate in English")
        case .dictationHistory: String(localized: "Keep dictation history")
        case .captureTrimmer: String(localized: "Recording Trimmer")
        case .captureEditor: String(localized: "Capture Editor")
        case .agentAnswer: String(localized: "Agent Answers")
        case .voiceAsk: String(localized: "Voice Ask")
        case .recording: String(localized: "Screen Recording")
        case .globeDictation: String(localized: "Globe Dictation")
        case .batteryChargeLimit: String(localized: "Charge Limit")
        case .batterySailing: String(localized: "Battery Sailing")
        case .batteryHeatProtection: String(localized: "Battery Heat Protection")
        case .batteryCalibration: String(localized: "Battery Calibration")
        case .keepAwake: String(localized: "Keep Awake")
        case .lidClosedAwake: String(localized: "Keep Awake with Lid Closed")
        case .cleanJunk: String(localized: "Junk")
        case .cleanHistory: String(localized: "Clean history")
        case .cleanAIData: String(localized: "AI data")
        case .cleanDisk: String(localized: "Disk analyzer")
        case .cleanPurge: String(localized: "Project purge")
        case .cleanOptimize: String(localized: "Optimize")
        case .cleanSystem: String(localized: "System root")
        case .settingsBackup: String(localized: "Settings Backup")
        case .machineSetupProfile: String(localized: "Machine Setup Profile")
        case .agentConfirmation: String(localized: "Agent Confirmation")
        case .eventReminder: String(localized: "Event Reminders")
        case .switcherQuitKey: String(localized: "Switcher Quit Key")
        case .linkQuickFixes: String(localized: "Link Quick Fixes")
        case .downloads: String(localized: "Downloads")
        case .downloadsAria2: String(localized: "Fast Downloads with aria2c")
        case .distill: String(localized: "Distill")
        case .distillTimestamps: String(localized: "Distill Timestamps")
        case .distillConvert: String(localized: "Convert Distill Folder")
        case .machBlockedDialogAlert: String(localized: "Other Mac Dialog Alerts")
        case .remoteScreen: String(localized: "Remote Screen")
        case .machMBPFans: String(localized: "Other Mac Fans")
        case .backupRunNow: String(localized: "Back Up Now")
        case .backupBrowseRestore: String(localized: "Browse and Restore Backups")
        case .quickLookSpace: String(localized: "Quick Look on Space")
        case .markdownFiles: String(localized: "Markdown Files")
        case .plainTextFiles: String(localized: "Plain Text Files")
        case .editorSpellChecking: String(localized: "Editor Spell Checking")
        }
    }

    var subtitle: String {
        switch self {
        case .audioPriority: String(localized: "Choose devices automatically when they connect or disconnect.")
        case .cleaningMode: String(localized: "Press Escape five times to exit; ends after 300 seconds.")
        case .appUpdates: String(localized: "Check installed apps for updates on demand.")
        case .macUpdate: String(localized: "Run maintenance only after confirmation.")
        case .tasks: String(localized: "Keep tasks on this Mac.")
        case .tasksSync: String(localized: "Exchange tasks with your paired Mac over Mac Link.")
        case .githubSearch: String(localized: "Search GitHub repositories and starred projects.")
        case .clearNotifications: String(localized: "Clear notifications from Notification Center. Requires English system language.")
        case .launcherAnswers: String(localized: "Currency answers using rates from NBP.")
        case .copyPath: String(localized: "Copy the frontmost document path or browser link.")
        case .smallCommands: String(localized: "Passwords, short links, noise control and AirDrop. Noise control requires English system language.")
        case .aiUsage: String(localized: "Read local AI usage on demand.")
        case .aiUsageOtherMac: String(localized: "Include usage from the other Mac.")
        case .machLink: String(localized: "Connect to a paired Mac on the local network.")
        case .commandRunner: String(localized: "Run commands from a host profile.")
        case .mediaTools: String(localized: "Compress media, make GIFs and extract text locally.")
        case .convertFiles: String(localized: "Convert local files beside the originals.")
        case .urlCleaner: String(localized: "Remove tracking parameters from copied links.")
        case .musicNowPlaying: String(localized: "Show track information in the island.")
        case .musicLastPlayer: String(localized: "Send playback controls to the last active player.")
        case .musicBlockAppleMusic: String(localized: "Prevent media keys from launching Apple Music.")
        case .spotifyConnect: String(localized: "Use this Mac as a Spotify playback device.")
        case .microphoneMute: String(localized: "Press F5 to mute or unmute microphones.")
        case .inUseMarks: String(localized: "Show when the camera or microphone is in use.")
        case .buildStats: String(localized: "Read a local build snapshot.")
        case .agentMCPServer: String(localized: "Nothing is exposed until the CLI is available.")
        case .agentChatTools: String(localized: "Add Notchcast tools to AI chat.")
        case .dictationEnglish: String(localized: "Use English for dictation.")
        case .island: String(localized: "Show the island at the top of the screen.")
        case .islandExternalDisplays: String(localized: "Show the island on external displays.")
        case .islandFullScreen: String(localized: "Show the island over full-screen apps.")
        case .islandHoverOpen: String(localized: "Open the island when the pointer hovers over it.")
        case .islandStatusMessages: String(localized: "Show status messages in the island.")
        case .islandLiveActivities: String(localized: "Show live activities in the island.")
        case .launcherFromIsland: String(localized: "Open the launcher from the island.")
        case .launcherNumberKeys: String(localized: "Open the first nine search results with Command-1 through Command-9.")
        case .launcherAliasSpace: String(localized: "Press Space after an exact alias to open its command.")
        case .systemMonitor: String(localized: "Monitor system performance.")
        case .monitorAlerts: String(localized: "Sample your Mac in the background while alerts are on.")
        case .fanControl: String(localized: "Control fans with the privileged helper.")
        case .accessoryBatteries: String(localized: "Show connected accessory battery levels.")
        case .accessoryNotices: String(localized: "Show accessory connections and low battery notices.")
        case .lowDiskWarning: String(localized: "Warns below \(10)% or \(30) GB free.")
        case .systemNotices: String(localized: "Wi-Fi, Tailscale and low battery notices in the island.")
        case .volumeLevels: String(localized: "Replaces the macOS volume overlay.")
        case .displayBrightness: String(localized: "Brightness keys control every display, external ones too.")
        case .quitProtection: String(localized: "Stops an app from quitting on a single slip.")
        case .liveTimers: String(localized: "Countdowns and alarms in the island.")
        case .dayCalendar: String(localized: "Calendar events on the Day page.")
        case .dayWeather: String(localized: "Forecast from Open-Meteo on the Day page.")
        case .agentActions: String(localized: "Expose actions and read-only state to local agents.")
        case .agentCLI: String(localized: "Accept local commands over a private Unix socket.")
        case .treadmillWalk: String(localized: "Walking pad controls are not available yet.")
        case .treadmillHistory: String(localized: "Keep walk totals, daily goals and lubrication reminders.")
        case .katana: String(localized: "Katana channels, tones and USB audio.")
        case .appearance: String(localized: "Themes and surface styles for the launcher, dialogs and HUDs.")
        case .agentSessions: String(localized: "Read local agent session metadata and token usage on demand.")
        case .openBotAgents: String(localized: "Read waiting items from local OpenBot agents.")
        case .agentThreads: String(localized: "Read active and recently finished agent threads on this Mac.")
        case .waitingAlerts: String(localized: "Notify when an agent needs approval or an answer.")
        case .agentPricing: String(localized: "Estimate API value from local agent token usage.")
        case .pastePlain: String(localized: "Paste text without formatting from the launcher.")
        case .finderCutPaste: String(localized: "Use ⌘X and ⌘V to move files in Finder.")
        case .finderRename: String(localized: "Use Hyper+R to rename the selection in Finder.")
        case .pasteImage: String(localized: "Command+V saves clipboard images as PNG files in Finder.")
        case .dayMarkets: String(localized: "Prices refresh every 3 minutes while Day is open.")
        case .colorPicker: String(localized: "Copy a color from anywhere on the screen.")
        case .screenshot: String(localized: "Capture an area, window or display.")
        case .screenText: String(localized: "Copy text from a selected screen area.")
        case .scrollingCapture: String(localized: "Copy a scrolling area as one image.")
        case .greenMaximize: String(localized: "Click the green button to maximize or restore; hold Option for macOS behavior.")
        case .middleClick: String(localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.")
        case .hideCommandM: String(localized: "Hide the front app instead of minimizing its window.")
        case .spacesOrder: String(localized: "Prevent automatic Spaces reordering and restore your setting when turned off.")
        case .showDesktop: String(localized: "Press F3 to show the desktop; press again to restore windows.")
        case .startupItems: String(localized: "Manage user LaunchAgents and inspect system items.")
        case .notificationCleanup: String(localized: "Dismiss disk-ejection alerts automatically.")
        case .sudoTouchID: String(localized: "Use Touch ID to authorize sudo.")
        case .killProcess: String(localized: "Adds a command to stop a process.")
        case .macSetup: String(localized: "Apply reversible macOS preferences.")
        case .aiFeaturesOff: String(localized: "Choose which Apple intelligence features to disable.")
        case .spotlightOff: String(localized: "Turn off Spotlight indexing.")
        case .privacyChoices: String(localized: "Choose macOS privacy restrictions.")
        case .typingTweaks: String(localized: "Changes system preferences after confirmation; some changes require signing out.")
        case .finderTweaks: String(localized: "Changes Finder preferences and restarts Finder after confirmation.")
        case .dockTweaks: String(localized: "Changes Dock preferences and restarts Dock after confirmation.")
        case .appleAppsTweaks: String(localized: "macOS requires your approval to install this restriction; remove it in System Settings.")
        case .iPhoneBackupTweaks: String(localized: "Changes system preferences after confirmation; some changes require signing out.")
        case .machRemote: String(localized: "Connect to the remote Mac using SSH.")
        case .backupStatus: String(localized: "Warns when backups fail or become stale.")
        case .linkHealth: String(localized: "Notify when the paired Mac disconnects or reconnects.")
        case .shelfBetweenMacs: String(localized: "Send small items to the paired Mac.")
        case .sendFiles: String(localized: "Send selected files to the remote Mac.")
        case .updateRemote: String(localized: "Run the update on the remote Mac.")
        case .archives: String(localized: "Extract opened archives beside the original file.")
        case .archivesInPlace: String(localized: "The archive shrinks while extracting.")
        case .archivesDefaultApp: String(localized: "Use Notchcast instead of Archive Utility to open archives.")
        case .torrents: String(localized: "Download magnet links and torrent files to Downloads.")
        case .torrentsUseIPhone: String(localized: "Use Wi-Fi and iPhone USB Personal Hotspot together.")
        case .torrentsKeepSharing: String(localized: "Upload as much as you download before stopping.")
        case .dictationIslandHUD: String(localized: "Show dictation status in the island.")
        case .dictationCleanup: String(localized: "Clean up final dictation transcripts.")
        case .dictationHistory: String(localized: "Save transcripts for later review.")
        case .captureTrimmer: String(localized: "Trim recordings and export MP4 or GIF files.")
        case .captureEditor: String(localized: "Mark up a capture and copy it.")
        case .agentAnswer: String(localized: "Reply to waiting agents.")
        case .voiceAsk: String(localized: "Voice Ask destination")
        case .recording: String(localized: "Record an area, window or display with system audio.")
        case .globeDictation: String(localized: "Tap Globe to start or finish dictation, or hold it to talk.")
        case .batteryChargeLimit: String(localized: "Stop charging at the selected limit.")
        case .batterySailing: String(localized: "Use battery power above the charge limit.")
        case .batteryHeatProtection: String(localized: "Pause charging when the battery is hot.")
        case .batteryCalibration: String(localized: "Run a full battery calibration cycle.")
        case .keepAwake: String(localized: "Prevent idle sleep for the selected duration.")
        case .lidClosedAwake: String(localized: "Keep awake while the lid is closed.")
        case .cleanJunk: String(localized: "Runs only when you click an action.")
        case .cleanHistory: String(localized: "Runs only when you click an action.")
        case .cleanAIData: String(localized: "Runs only when you click an action.")
        case .cleanDisk: String(localized: "Runs only when you click an action.")
        case .cleanPurge: String(localized: "Runs only when you click an action.")
        case .cleanOptimize: String(localized: "Runs only when you click an action.")
        case .cleanSystem: String(localized: "Runs only when you click an action.")
        case .settingsBackup: String(localized: "Back up safe Notchcast preferences daily.")
        case .machineSetupProfile: String(localized: "Plan portable setup imports and exports.")
        case .agentConfirmation: String(localized: "Ask before allowing agent requests.")
        case .eventReminder: String(localized: "Show calendar alerts in the island.")
        case .switcherQuitKey: String(localized: "Press Q in an empty window search to quit the selected app.")
        case .linkQuickFixes: String(localized: "Offer manual fixes for connection problems.")
        case .downloads: String(localized: "Download video, audio, transcripts and webpages from clipboard links.")
        case .downloadsAria2: String(localized: "Use aria2c for faster media downloads when it is installed.")
        case .distill: String(localized: "Save links and transcribe media into your Distill folder.")
        case .distillTimestamps: String(localized: "Include approximate chunk timestamps in Distill transcripts.")
        case .distillConvert: String(localized: "Convert files in your Distill folder to Markdown or text.")
        case .machBlockedDialogAlert: String(localized: "Check for system dialogs on the paired Mac on demand.")
        case .remoteScreen: String(localized: "Request screen sharing with the paired Mac.")
        case .machMBPFans: String(localized: "Control fans on the paired Mac.")
        case .backupRunNow: String(localized: "Allow starting the configured backup job.")
        case .backupBrowseRestore: String(localized: "Browse snapshots and restore into a new Downloads folder.")
        case .quickLookSpace: String(localized: "Preview an arrow-selected file with Space.")
        case .markdownFiles: String(localized: "Edit Markdown documents outside the notes folder.")
        case .plainTextFiles: String(localized: "Edit plain text while preserving its file encoding.")
        case .editorSpellChecking: String(localized: "Check spelling in the editor.")
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
        .agentMCPServer,
        .agentChatTools,
        .voiceAsk,
        .agentMCPServer,
        .agentChatTools,
        .cleanSystem,
        .linkQuickFixes,
        .remoteScreen,
        .machMBPFans,
        .macSetup,
        .machineSetupProfile,
    ]

    static var systemToolsSettingsFeatures: [Self] {
        [.startupItems, .notificationCleanup, .sudoTouchID, .killProcess,
         .macSetup, .aiFeaturesOff, .spotlightOff, .privacyChoices].filter(\.isWired)
    }

    /// Shows only in the island, so its switch follows the island switch in Settings.
    var needsIsland: Bool {
        if isSystemFeature || isSystemTweak || settingsGroup == .clean { return false }
        return switch self {
        case .tasks: false
        case .tasksSync: false
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
        case .waitingAlerts: false
        case .agentPricing: false
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
