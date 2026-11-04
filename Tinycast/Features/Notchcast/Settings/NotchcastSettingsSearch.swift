import Foundation

/// One line per anchor and per entry, so branches that add rows merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension SettingsAnchor {
    static func notchcast(feature: NotchcastFeature) -> Self {
        let module = NotchcastSettingsModule.module(of: feature)
        let group = module.groups.first { $0.items.contains { $0.feature == feature } }!
        return Self(tab: module.tab, title: group.title)
    }

    static let notchcastAppearance = Self.notchcast(feature: .appearance)
    static let notchcastClean = Self.notchcast(feature: .cleanJunk)
    static let notchcastCleaning = Self.notchcast(feature: .cleaningMode)
    static let notchcastAppUpdates = Self.notchcast(feature: .appUpdates)
    static let notchcastMacUpdate = Self.notchcast(feature: .macUpdate)
    static let notchcastTweaksApps = Self.notchcast(feature: .typingTweaks)
    static let notchcastTasks = Self.notchcast(feature: .tasks)
    static let notchcastArchives = Self.notchcast(feature: .archives)
    static let notchcastBuildStats = Self.notchcast(feature: .buildStats)
    static let notchcastAlerts = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAlertCPU = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAlertTemperature = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAlertMemory = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAlertDisk = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAlertBattery = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAlertBatteryTemperature = Self.notchcast(feature: .monitorAlerts)
    static let notchcastAccessories = Self.notchcast(feature: .accessoryBatteries)
    static let notchcastChargePercent = Self.notchcast(feature: .batteryChargeLimit)
    static let notchcastAwakeDuration = Self.notchcast(feature: .keepAwake)
    static let notchcastMonitor = Self.notchcast(feature: .systemMonitor)
    static let notchcastFanMode = Self.notchcast(feature: .fanControl)
    static let notchcastIsland = Self.notchcast(feature: .island)
    static let notchcastOptions = Self.notchcast(feature: .islandHoverOpen)
    static let notchcastLauncher = Self.notchcast(feature: .launcherFromIsland)
    static let notchcastSystem = Self.notchcast(feature: .greenMaximize)
    static let notchcastActivities = Self.notchcast(feature: .dayCalendar)
    static let notchcastMusic = Self.notchcast(feature: .musicNowPlaying)
    // ai-design-check-ignore-next-line sentence-case -- Spotify Connect is a product name.
    static let notchcastSpotify = Self.notchcast(feature: .spotifyConnect)
    static let notchcastMicrophone = Self.notchcast(feature: .microphoneMute)
    static let notchcastBrightness = Self.notchcast(feature: .displayBrightness)
    static let notchcastQuitProtection = Self.notchcast(feature: .quitProtection)
    static let notchcastTimers = Self.notchcast(feature: .liveTimers)
    static let notchcastDay = Self.notchcast(feature: .dayCalendar)
    static let notchcastTweaks = Self.notchcast(feature: .startupItems)
    static let notchcastDownloads = Self.notchcast(feature: .downloads)
    static let notchcastLauncherTools = Self.notchcast(feature: .githubSearch)
    static let notchcastAIUsage = Self.notchcast(feature: .machLink)
    static let notchcastTorrents = Self.notchcast(feature: .torrents)
    static let notchcastPaste = Self.notchcast(feature: .pastePlain)
    static let notchcastRemoteMac = Self.notchcast(feature: .machRemote)
    static let notchcastFinder = Self.notchcast(feature: .finderRename)
    static let notchcastCaptureAndDictation = Self.notchcast(feature: .screenshot)
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = {
        let candidates: [SettingsSearchEntry] =
        NotchcastSettingsModule.allCases.flatMap { module in
            (SettingsTab.allCases.contains {
                NotchcastSettingsModule(tab: $0) == nil && $0.title == module.title
            } ? [] : [.init(pane: module.tab)]) + module.visibleGroups.flatMap { group -> [SettingsSearchEntry] in
                let anchor = SettingsAnchor(tab: module.tab, title: group.title)
                let header: [SettingsSearchEntry] = group.items.compactMap(\.feature).contains {
                    $0.title == group.title.resolved()
                } ? [] : [.init(group: anchor, group.title, keywords: [module.title])]
                return header +
                    group.items.compactMap(\.feature).filter(\.isWired).map { feature in
                        .init(feature: feature, anchor: anchor, keywords: [module.title])
                    }
            }
        } + [
        .init(group: .notchcast(feature: .audioPriority), "Audio device priority", keywords: ["sound", "outputs", "microphones"]),
        .init(group: .notchcast(feature: .cleanJunk), "Junk", keywords: ["trash", "cache"]),
        .init(group: .notchcast(feature: .cleanHistory), "Clean history", keywords: ["restore", "runs"]),
        .init(group: .notchcast(feature: .cleanAIData), "AI data", keywords: ["claude", "codex", "opencode"]),
        .init(group: .notchcast(feature: .cleanDisk), "Disk analyzer", keywords: ["folder", "size"]),
        .init(group: .notchcast(feature: .cleanPurge), "Project purge", keywords: ["projects", "build", "artifacts"]),
        .init(group: .notchcast(feature: .cleanOptimize), "Optimize", keywords: ["quick look", "download history", "open with"]),
        .init(group: .notchcast(feature: .cleaningMode), "Cleaning mode"),
        .init(group: .notchcast(feature: .appUpdates), "App updates"),
        .init(group: .notchcast(feature: .macUpdate), "Update this Mac"),
        .init(group: .notchcast(feature: .tasks), "Tasks", keywords: ["todo", "task store", "local tasks"]),
        .init(group: .notchcast(feature: .tasks), "Import Todoist JSON export…", keywords: ["json", "local file", "import"]),
        .init(group: .notchcast(feature: .urlCleaner), "URL cleaner", keywords: ["tracking", "clipboard", "parameters"]),
        .init(group: .notchcast(feature: .appearance), "Custom appearance", keywords: ["enable", "colours", "colors", "theme"]),
        .init(group: .notchcastAppearance, "Surface", keywords: ["glass", "black", "matte", "material"]),
        .init(group: .notchcastAppearance, "Light theme", keywords: ["palette", "raycast", "ray.so"]),
        .init(group: .notchcastAppearance, "Dark theme", keywords: ["palette", "raycast", "ray.so"]),
        .init(group: .notchcastAppearance, "Theme backdrop", keywords: ["opacity", "background", "transparency"]),
        .init(group: .notchcastAppearance, "Import from link", keywords: ["theme", "raycast", "ray.so", "url"]),
        .init(group: .notchcast(feature: .archives), "Archives", keywords: ["extract", "zip", "7z", "rar", "tar", "tgz", "001", "hatchzip"]),
        .init(group: .notchcast(feature: .archivesInPlace), "Extract in place", keywords: ["shrink", "space", "destructive"]),
        .init(group: .notchcast(feature: .archivesDefaultApp), "Open archives with Notchcast", keywords: ["default", "handler", "Archive Utility"]),
        .init(group: .notchcast(feature: .monitorAlerts), "Monitor Alerts"),
        .init(group: .notchcastAlertCPU, "CPU usage threshold"),
        .init(group: .notchcastAlertTemperature, "CPU temperature threshold"),
        .init(group: .notchcastAlertMemory, "Memory pressure threshold"),
        .init(group: .notchcastAlertDisk, "Disk free threshold"),
        .init(group: .notchcastAlertBattery, "Battery threshold"),
        .init(group: .notchcastAlertBatteryTemperature, "Battery temperature threshold"),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(group: .notchcastTweaksApps, "Disable autocorrect"),
        .init(group: .notchcastTweaksApps, "Disable smart punctuation"),
        .init(group: .notchcastTweaksApps, "Disable double-space period"),
        .init(group: .notchcastTweaksApps, "Disable auto-capitalization"),
        .init(group: .notchcastTweaksApps, "Enable key repeat"),
        .init(group: .notchcastTweaksApps, "Show file extensions"),
        .init(group: .notchcastTweaksApps, "Show hidden files"),
        .init(group: .notchcastTweaksApps, "Show path bar"),
        .init(group: .notchcastTweaksApps, "Show status bar"),
        .init(group: .notchcastTweaksApps, "Keep folders first"),
        .init(group: .notchcastTweaksApps, "Search current folder"),
        .init(group: .notchcastTweaksApps, "Disable extension warning"),
        .init(group: .notchcastTweaksApps, "Show path in title"),
        .init(group: .notchcastTweaksApps, "Avoid network metadata"),
        .init(group: .notchcastTweaksApps, "Remove trash after 30 days"),
        .init(group: .notchcastTweaksApps, "Save locally"),
        .init(group: .notchcastTweaksApps, "Expand save dialogs"),
        .init(group: .notchcastTweaksApps, "Use list view"),
        .init(group: .notchcastTweaksApps, "Avoid USB metadata"),
        .init(group: .notchcastTweaksApps, "Hide desktop disks"),
        .init(group: .notchcastTweaksApps, "Hide recent apps"),
        .init(group: .notchcastTweaksApps, "Remove auto-hide delay"),
        .init(group: .notchcastTweaksApps, "Disable launch animation"),
        .init(group: .notchcastTweaksApps, "Minimize into app"),
        .init(group: .notchcastTweaksApps, "Disable window animations"),
        .init(group: .notchcastTweaksApps, "Remove tiled window margins"),
        .init(group: .notchcastTweaksApps, "Remove screenshot shadow"),
        .init(group: .notchcastTweaksApps, "Disable click to desktop"),
        .init(group: .notchcastTweaksApps, "Hide desktop widgets"),
        .init(group: .notchcast(feature: .typingTweaks), "Typing"),
        .init(group: .notchcastTweaksApps, "Show library"),
        .init(group: .notchcast(feature: .appleAppsTweaks), "Restrict gaming"),
        .init(group: .notchcast(feature: .appleAppsTweaks), "Restrict iPhone mirroring"),
        .init(group: .notchcast(feature: .appleAppsTweaks), "Restrict music service"),
        .init(group: .notchcast(feature: .appleAppsTweaks), "Restrict book store"),
        .init(group: .notchcast(feature: .finderTweaks), "Finder"),
        .init(group: .notchcast(feature: .dockTweaks), "Dock and windows"),
        .init(group: .notchcast(feature: .appleAppsTweaks), "Apple apps"),
        .init(group: .notchcast(feature: .iPhoneBackupTweaks), "iPhone backup"),
        .init(group: .notchcastTweaksApps, "Key repeat speed"),
        .init(group: .notchcastTweaksApps, "Key repeat delay"),
        .init(group: .notchcastTweaksApps, "New Finder windows"),
        .init(group: .notchcast(feature: .iPhoneBackupTweaks), "Turn off iPhone auto backups"),
        .init(group: .notchcast(feature: .iPhoneBackupTweaks), "iPhone backup folder"),
        .init(group: .notchcast(feature: .island), "Island", keywords: ["notch", "enable", "dynamic island"]),
        .init(group: .notchcast(feature: .islandExternalDisplays), "External Displays", keywords: ["monitor", "screen", "display", "hover delay"]),
        .init(group: .notchcast(feature: .islandFullScreen), "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(group: .notchcast(feature: .islandHoverOpen), "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(group: .notchcast(feature: .islandStatusMessages), "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(group: .notchcast(feature: .islandLiveActivities), "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(group: .notchcast(feature: .launcherFromIsland), "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(group: .notchcast(feature: .launcherNumberKeys), "Launcher Number Keys", keywords: ["command", "results", "1", "9"]),
        .init(group: .notchcast(feature: .launcherAliasSpace), "Alias and Space", keywords: ["alias", "space", "arguments"]),
        .init(group: .notchcast(feature: .quickLookSpace), "Quick Look on Space", keywords: ["file", "preview", "markdown"]),
        .init(group: .notchcast(feature: .systemMonitor), "System Monitor", keywords: ["cpu", "memory", "temperature"]),
        .init(group: .notchcast(feature: .fanControl), "Fan Control", keywords: ["cooling", "rpm"]),
        .init(group: .notchcast(feature: .accessoryBatteries), "Accessory batteries", keywords: ["bluetooth", "charging", "mouse", "keyboard"]),
        .init(group: .notchcastFanMode, "Fan mode"),
        .init(group: .notchcast(feature: .batteryChargeLimit), "Charge Limit"),
        .init(group: .notchcast(feature: .batterySailing), "Battery Sailing"),
        .init(group: .notchcast(feature: .batteryHeatProtection), "Battery Heat Protection"),
        .init(group: .notchcast(feature: .batteryCalibration), "Battery Calibration"),
        .init(group: .notchcast(feature: .keepAwake), "Keep Awake"),
        .init(group: .notchcast(feature: .lidClosedAwake), "Keep Awake with Lid Closed"),
        .init(group: .notchcastChargePercent, "Charge limit percent"),
        .init(group: .notchcastAwakeDuration, "Keep-awake duration"),
        .init(group: .notchcast(feature: .island), "Toggle Island"),
        .init(group: .notchcast(feature: .colorPicker), "Pick Color", keywords: ["colour", "eyedropper", "sample"]),
        .init(group: .notchcast(feature: .colorPicker), "Color format", keywords: ["colour", "hex", "rgb", "hsl"]),
        .init(group: .notchcast(feature: .screenshot), "Screenshots", keywords: ["screen capture", "image"]),
        .init(group: .notchcast(feature: .screenText), "Capture Text", keywords: ["ocr", "recognize", "barcode", "qr"]),
        .init(group: .notchcast(feature: .screenText), "Remove line breaks"),
        .init(group: .notchcast(feature: .scrollingCapture), "Scrolling Capture", keywords: ["stitch", "screenshot"]),
        .init(group: .notchcast(feature: .dictationEnglish), "Dictate in English", keywords: ["Globe", "translate"]),
        .init(group: .notchcast(feature: .globeDictation), "Globe Dictation", keywords: ["fn", "microphone", "hold to talk"]),
        .init(group: .notchcast(feature: .screenshot), "Screenshot destination", keywords: ["clipboard", "file", "save"]),
        .init(group: .notchcast(feature: .screenshot), "Screenshot folder", keywords: ["directory", "desktop"]),
        .init(group: .notchcast(feature: .dictationCleanup), "AI cleanup"),
        .init(group: .notchcast(feature: .dictationHistory), "Keep dictation history"),
        .init(group: .notchcast(feature: .dictationHistory), "Delete history"),
        .init(group: .notchcast(feature: .dictationCleanup), "Cleanup endpoint"),
        .init(group: .notchcast(feature: .dictationCleanup), "Cleanup effort"),
        .init(group: .notchcast(feature: .dictationCleanup), "Cleanup prompt addition"),
        .init(group: .notchcast(feature: .dictationCleanup), "Cleanup vocabulary"),
        .init(group: .notchcast(feature: .dictationCleanup), "Cleanup API key"),
        .init(group: .notchcast(feature: .displayBrightness), "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(group: .notchcast(feature: .editorSpellChecking), "Editor Spell Checking", keywords: ["editor", "spelling", "notes"]),
        .init(group: .notchcast(feature: .volumeLevels), "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(group: .notchcast(feature: .systemNotices), "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(group: .notchcast(feature: .lowDiskWarning), "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(group: .notchcast(feature: .quitProtection), "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(group: .notchcast(feature: .agentActions), "Agent access"),
        .init(group: .notchcast(feature: .agentCLI), "Command line tool"),
        .init(group: .notchcast(feature: .liveTimers), "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(group: .notchcast(feature: .dayCalendar), "Calendar", keywords: ["events", "day", "schedule"]),
        .init(group: .notchcast(feature: .convertFiles), "Convert Files", keywords: ["convert", "pdf", "formats"]),
        .init(group: .notchcast(feature: .mediaTools), "Media Tools", keywords: ["compress", "gif", "resize", "text"]),
        .init(group: .notchcast(feature: .commandRunner), "Command Runner", keywords: ["catalogue", "shell", "tasks"]),
        .init(group: .notchcast(feature: .greenMaximize), "Green Button Maximizes", keywords: ["window", "maximize", "restore"]),
        .init(group: .notchcast(feature: .middleClick), "Trackpad Middle Click", keywords: ["three finger", "mouse", "trackpad"]),
        .init(group: .notchcast(feature: .showDesktop), "Show Desktop with F3", keywords: ["mission control", "windows"]),
        .init(group: .notchcast(feature: .hideCommandM), "Hide with ⌘M", keywords: ["minimize", "command m"]),
        .init(group: .notchcast(feature: .spacesOrder), "Keep Spaces in a fixed order", keywords: ["desktop", "reorder"]),
        .init(group: .notchcast(feature: .greenMaximize), "Excluded app bundle IDs (comma-separated)", keywords: ["green button", "maximize", "exceptions"]),
        .init(group: .notchcast(feature: .settingsBackup), "Settings Backup", keywords: ["backup", "preferences", "daily"]),
        .init(group: .notchcast(feature: .startupItems), "Startup Items", keywords: ["launchagents"]),
        .init(group: .notchcast(feature: .notificationCleanup), "Notification Cleanup", keywords: ["disk", "ejection"]),
        .init(group: .notchcast(feature: .sudoTouchID), "Touch ID for sudo", keywords: ["authentication"]),
        .init(group: .notchcast(feature: .spotlightOff), "Spotlight Indexing Off", keywords: ["search"]),
        .init(group: .notchcast(feature: .downloads), "Downloads", keywords: ["video", "audio", "transcript", "webpage", "clipboard"]),
        .init(group: .notchcast(feature: .downloadsAria2), "Fast Downloads with aria2c", keywords: ["download", "speed", "aria2"]),
        .init(group: .notchcast(feature: .distill), "Distill", keywords: ["links", "transcribe", "media", "queue"]),
        .init(group: .notchcast(feature: .distillTimestamps), "Distill Timestamps", keywords: ["transcript", "time", "chunks"]),
        .init(group: .notchcast(feature: .distillConvert), "Convert Distill Folder", keywords: ["markdown", "pdf", "ocr", "files"]),
        .init(group: .notchcast(feature: .machLink), "Mac Link", keywords: ["pair", "network"]),
        .init(group: .notchcast(feature: .clearNotifications), "Clear Notifications", keywords: ["notification center", "accessibility"]),
        .init(group: .notchcast(feature: .copyPath), "Copy Path", keywords: ["finder", "browser", "document", "link"]),
        .init(group: .notchcast(feature: .smallCommands), "Small Commands", keywords: ["password", "shorten", "noise", "airdrop"]),
        .init(group: .notchcast(feature: .shelfBetweenMacs), "Shelf between Macs", keywords: ["send", "files", "text"]),
        .init(group: .notchcast(feature: .linkHealth), "Link Health", keywords: ["connection", "latency", "peer"]),
        .init(group: .notchcast(feature: .backupStatus), "Backup Status", keywords: ["backup", "stale", "failure", "restore"]),
        .init(group: .notchcast(feature: .machRemote), "Remote Mac", keywords: ["ssh", "terminal", "Remote Mac address"]),
        .init(group: .notchcast(feature: .sendFiles), "Send to Remote Mac", keywords: ["files", "Finder"]),
        .init(group: .notchcast(feature: .updateRemote), "Update Remote Mac", keywords: ["update", "ssh"]),
        .init(group: .notchcast(feature: .machRemote), "Remote Mac address", keywords: ["ssh", "host", "alias"]),
        .init(group: .notchcast(feature: .machRemote), "Remote terminal directory"),
        .init(group: .notchcast(feature: .machRemote), "Remote update script path"),
        .init(group: .notchcast(feature: .backupStatus), "Backup status file path"),
        .init(group: .notchcast(feature: .machLink), "Pairing code", keywords: ["pair", "unpair"]),
        .init(group: .notchcast(feature: .musicNowPlaying), "Show what is playing", keywords: ["now playing", "track", "cover", "media", "song"]),
        .init(group: .notchcast(feature: .musicLastPlayer), "Resume last player", keywords: ["play key", "spotify", "media key"]),
        .init(group: .notchcast(feature: .musicBlockAppleMusic), "Stop Apple Music opening on media keys", keywords: ["music app", "itunes", "media key", "play key"]),
        .init(group: .notchcast(feature: .spotifyConnect), "Spotify Connect speaker", keywords: ["soloist", "spotify", "speaker", "connect", "phone"]),
        .init(group: .notchcast(feature: .spotifyConnect), "API key", keywords: ["soloist", "key", "developer"]),
        .init(group: .notchcast(feature: .spotifyConnect), "Device name", keywords: ["soloist", "speaker name"]),
        .init(group: .notchcast(feature: .spotifyConnect), "Download Soloist", keywords: ["soloist", "update", "build", "expiry"]),
        .init(group: .notchcast(feature: .microphoneMute), "Microphone mute", keywords: ["mute", "f5", "mic"]),
        .init(group: .notchcast(feature: .torrents), "Torrents", keywords: ["magnet", "torrent", "download"]),
        .init(group: .notchcast(feature: .torrentsUseIPhone), "Use a plugged-in iPhone for big downloads", keywords: ["wifi", "iphone", "usb", "hotspot", "network"]),
        .init(group: .notchcast(feature: .torrentsKeepSharing), "Keep sharing until ratio 1.0", keywords: ["seed", "seeding", "upload"]),
        .init(group: .notchcast(feature: .torrents), "aria2c", keywords: ["install", "homebrew", "tool", "path"]),
        .init(group: .notchcast(feature: .pastePlain), "Paste Plain Text", keywords: ["hyper", "clipboard", "formatting"]),
        .init(group: .notchcast(feature: .finderCutPaste), "Finder Cut and Paste", keywords: ["files", "move", "clipboard"]),
        .init(group: .notchcast(feature: .finderRename), "Finder Rename", keywords: ["hyper", "shortcut", "return"]),
        .init(group: .notchcast(feature: .finderCutPaste), "Cut and move files", keywords: ["copy", "escape", "cancel"]),
        .init(group: .notchcast(feature: .finderRename), "Rename selection", keywords: ["hyper", "shortcut", "return"]),
        .init(group: .notchcast(feature: .pasteImage), "Paste Image in Finder", keywords: ["png", "clipboard", "file"]),
    ]
        var entries: [SettingsSearchEntry] = []
        for candidate in candidates {
            if let index = entries.firstIndex(where: { $0.id == candidate.id }) {
                entries[index] = SettingsSearchEntry(merging: entries[index], keywords: candidate.keywords)
            } else {
                entries.append(candidate)
            }
        }
        return entries
    }()
}

extension SettingsSearchEntry {
    init(feature: NotchcastFeature, anchor: SettingsAnchor, keywords: [String]) {
        tab = anchor.tab
        target = .row(anchor, feature.title)
        title = feature.title
        self.keywords = keywords + [feature.title]
    }

    init(merging entry: Self, keywords: [String]) {
        tab = entry.tab
        target = entry.target
        title = entry.title
        self.keywords = entry.keywords + keywords
    }
}
