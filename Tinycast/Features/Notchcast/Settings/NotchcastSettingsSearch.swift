import Foundation

/// One line per anchor and per entry, so branches that add rows merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension SettingsAnchor {
    static let notchcastBackupSettingsFile = Self(tab: .notchcastBackups, title: LocalizedStringResource("Settings File"))
    static let notchcastBackupExport = Self(tab: .notchcastBackups, title: "Export")
    static let notchcastBackupImport = Self(tab: .notchcastBackups, title: "Import")
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
        .init(.notchcastBackupSettingsFile, "Sync settings file"),
        .init(.notchcastBackupExport, "Export Backup"),
        .init(.notchcastBackupImport, "Backup File"),
        .init(group: .notchcast(feature: .audioPriority), LocalizedStringResource("Audio device priority", table: "Notchcast"), keywords: ["sound", "outputs", "microphones"]),
        .init(group: .notchcast(feature: .cleanJunk), LocalizedStringResource("Junk", table: "Notchcast"), keywords: ["trash", "cache"]),
        .init(group: .notchcast(feature: .cleanHistory), LocalizedStringResource("Clean history", table: "Notchcast"), keywords: ["restore", "runs"]),
        .init(group: .notchcast(feature: .cleanAIData), LocalizedStringResource("AI data", table: "Notchcast"), keywords: ["claude", "codex", "opencode"]),
        .init(group: .notchcast(feature: .cleanDisk), LocalizedStringResource("Disk analyzer", table: "Notchcast"), keywords: ["folder", "size"]),
        .init(group: .notchcast(feature: .cleanPurge), LocalizedStringResource("Project purge", table: "Notchcast"), keywords: ["projects", "build", "artifacts"]),
        .init(group: .notchcast(feature: .cleanOptimize), LocalizedStringResource("Optimize", table: "Notchcast"), keywords: ["quick look", "download history", "open with"]),
        .init(group: .notchcast(feature: .cleaningMode), LocalizedStringResource("Cleaning mode", table: "Notchcast")),
        .init(group: .notchcast(feature: .appUpdates), LocalizedStringResource("App updates", table: "Notchcast")),
        .init(group: .notchcast(feature: .macUpdate), LocalizedStringResource("Update this Mac", table: "Notchcast")),
        .init(group: .notchcast(feature: .tasks), LocalizedStringResource("Tasks", table: "Notchcast"), keywords: ["todo", "task store", "local tasks"]),
        .init(group: .notchcast(feature: .tasks), LocalizedStringResource("Import Todoist JSON export…", table: "Notchcast"), keywords: ["json", "local file", "import"]),
        .init(group: .notchcast(feature: .urlCleaner), LocalizedStringResource("URL cleaner", table: "Notchcast"), keywords: ["tracking", "clipboard", "parameters"]),
        .init(group: .notchcast(feature: .appearance), LocalizedStringResource("Custom appearance", table: "Notchcast"), keywords: ["enable", "colours", "colors", "theme"]),
        .init(group: .notchcastAppearance, LocalizedStringResource("Surface", table: "Notchcast"), keywords: ["glass", "black", "matte", "material"]),
        .init(group: .notchcastAppearance, LocalizedStringResource("Light theme", table: "Notchcast"), keywords: ["palette", "raycast", "ray.so"]),
        .init(group: .notchcastAppearance, LocalizedStringResource("Dark theme", table: "Notchcast"), keywords: ["palette", "raycast", "ray.so"]),
        .init(group: .notchcastAppearance, LocalizedStringResource("Theme backdrop", table: "Notchcast"), keywords: ["opacity", "background", "transparency"]),
        .init(group: .notchcastAppearance, LocalizedStringResource("Import from link", table: "Notchcast"), keywords: ["theme", "raycast", "ray.so", "url"]),
        .init(group: .notchcast(feature: .archives), "Archives", keywords: ["extract", "zip", "7z", "rar", "tar", "tgz", "001", "hatchzip"]),
        .init(group: .notchcast(feature: .archivesInPlace), LocalizedStringResource("Extract in place", table: "Notchcast"), keywords: ["shrink", "space", "destructive"]),
        .init(group: .notchcast(feature: .archivesDefaultApp), LocalizedStringResource("Open archives with Notchcast", table: "Notchcast"), keywords: ["default", "handler", "Archive Utility"]),
        .init(group: .notchcast(feature: .monitorAlerts), LocalizedStringResource("Monitor Alerts", table: "Notchcast")),
        .init(group: .notchcastAlertCPU, LocalizedStringResource("CPU usage threshold", table: "Notchcast")),
        .init(group: .notchcastAlertTemperature, LocalizedStringResource("CPU temperature threshold", table: "Notchcast")),
        .init(group: .notchcastAlertMemory, LocalizedStringResource("Memory pressure threshold", table: "Notchcast")),
        .init(group: .notchcastAlertDisk, LocalizedStringResource("Disk free threshold", table: "Notchcast")),
        .init(group: .notchcastAlertBattery, LocalizedStringResource("Battery threshold", table: "Notchcast")),
        .init(group: .notchcastAlertBatteryTemperature, LocalizedStringResource("Battery temperature threshold", table: "Notchcast")),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable autocorrect", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable smart punctuation", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable double-space period", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable auto-capitalization", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Enable key repeat", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Show file extensions", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Show hidden files", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Show path bar", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Show status bar", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Keep folders first", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Search current folder", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable extension warning", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Show path in title", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Avoid network metadata", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Remove trash after 30 days", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Save locally", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Expand save dialogs", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Use list view", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Avoid USB metadata", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Hide desktop disks", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Hide recent apps", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Remove auto-hide delay", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable launch animation", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Minimize into app", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable window animations", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Remove tiled window margins", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Remove screenshot shadow", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Disable click to desktop", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Hide desktop widgets", table: "Notchcast")),
        .init(group: .notchcast(feature: .typingTweaks), LocalizedStringResource("Typing", table: "Notchcast")),
        .init(group: .notchcast(feature: .finderTweaks), LocalizedStringResource("Show library", table: "Notchcast")),
        .init(group: .notchcast(feature: .appleAppsTweaks), LocalizedStringResource("Restrict gaming", table: "Notchcast")),
        .init(group: .notchcast(feature: .appleAppsTweaks), LocalizedStringResource("Restrict iPhone mirroring", table: "Notchcast")),
        .init(group: .notchcast(feature: .appleAppsTweaks), LocalizedStringResource("Restrict music service", table: "Notchcast")),
        .init(group: .notchcast(feature: .appleAppsTweaks), LocalizedStringResource("Restrict book store", table: "Notchcast")),
        .init(group: .notchcast(feature: .finderTweaks), LocalizedStringResource("Finder", table: "Notchcast")),
        .init(group: .notchcast(feature: .dockTweaks), LocalizedStringResource("Dock and windows", table: "Notchcast")),
        .init(group: .notchcast(feature: .appleAppsTweaks), LocalizedStringResource("Apple apps", table: "Notchcast")),
        .init(group: .notchcast(feature: .iPhoneBackupTweaks), LocalizedStringResource("iPhone backup", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Key repeat speed", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("Key repeat delay", table: "Notchcast")),
        .init(group: .notchcastTweaksApps, LocalizedStringResource("New Finder windows", table: "Notchcast")),
        .init(group: .notchcast(feature: .iPhoneBackupTweaks), LocalizedStringResource("Turn off iPhone auto backups", table: "Notchcast")),
        .init(group: .notchcast(feature: .iPhoneBackupTweaks), LocalizedStringResource("iPhone backup folder", table: "Notchcast")),
        .init(group: .notchcast(feature: .island), LocalizedStringResource("Island", table: "Notchcast"), keywords: ["notch", "enable", "dynamic island"]),
        .init(group: .notchcast(feature: .islandExternalDisplays), LocalizedStringResource("External Displays", table: "Notchcast"), keywords: ["monitor", "screen", "display", "hover delay"]),
        .init(group: .notchcast(feature: .islandFullScreen), LocalizedStringResource("Full-Screen Apps", table: "Notchcast"), keywords: ["fullscreen", "full screen", "video"]),
        .init(group: .notchcast(feature: .islandHoverOpen), LocalizedStringResource("Open on Hover", table: "Notchcast"), keywords: ["pointer", "mouse", "hover"]),
        .init(group: .notchcast(feature: .islandStatusMessages), LocalizedStringResource("Status Messages", table: "Notchcast"), keywords: ["hud", "toast", "message"]),
        .init(group: .notchcast(feature: .islandLiveActivities), LocalizedStringResource("Live Activities", table: "Notchcast"), keywords: ["now playing", "timer", "activity"]),
        .init(group: .notchcast(feature: .launcherFromIsland), LocalizedStringResource("Launcher from Island", table: "Notchcast"), keywords: ["palette", "search", "open"]),
        .init(group: .notchcast(feature: .launcherNumberKeys), LocalizedStringResource("Launcher Number Keys", table: "Notchcast"), keywords: ["command", "results", "1", "9"]),
        .init(group: .notchcast(feature: .launcherAliasSpace), LocalizedStringResource("Alias and Space", table: "Notchcast"), keywords: ["alias", "space", "arguments"]),
        .init(group: .notchcast(feature: .quickLookSpace), LocalizedStringResource("Quick Look on Space", table: "Notchcast"), keywords: ["file", "preview", "markdown"]),
        .init(group: .notchcast(feature: .systemMonitor), LocalizedStringResource("System Monitor", table: "Notchcast"), keywords: ["cpu", "memory", "temperature"]),
        .init(group: .notchcast(feature: .fanControl), LocalizedStringResource("Fan Control", table: "Notchcast"), keywords: ["cooling", "rpm"]),
        .init(group: .notchcast(feature: .accessoryBatteries), LocalizedStringResource("Accessory batteries", table: "Notchcast"), keywords: ["bluetooth", "charging", "mouse", "keyboard"]),
        .init(group: .notchcastFanMode, LocalizedStringResource("Fan mode", table: "Notchcast")),
        .init(group: .notchcast(feature: .batteryChargeLimit), LocalizedStringResource("Charge Limit", table: "Notchcast")),
        .init(group: .notchcast(feature: .batterySailing), LocalizedStringResource("Battery Sailing", table: "Notchcast")),
        .init(group: .notchcast(feature: .batteryHeatProtection), LocalizedStringResource("Battery Heat Protection", table: "Notchcast")),
        .init(group: .notchcast(feature: .batteryCalibration), LocalizedStringResource("Battery Calibration", table: "Notchcast")),
        .init(group: .notchcast(feature: .keepAwake), LocalizedStringResource("Keep Awake", table: "Notchcast")),
        .init(group: .notchcast(feature: .lidClosedAwake), LocalizedStringResource("Keep Awake with Lid Closed", table: "Notchcast")),
        .init(group: .notchcastChargePercent, LocalizedStringResource("Charge limit percent", table: "Notchcast")),
        .init(group: .notchcastAwakeDuration, LocalizedStringResource("Keep-awake duration", table: "Notchcast")),
        .init(group: .notchcast(feature: .island), LocalizedStringResource("Toggle Island", table: "Notchcast")),
        .init(group: .notchcast(feature: .colorPicker), LocalizedStringResource("Pick Color", table: "Notchcast"), keywords: ["colour", "eyedropper", "sample"]),
        .init(group: .notchcast(feature: .colorPicker), LocalizedStringResource("Color format", table: "Notchcast"), keywords: ["colour", "hex", "rgb", "hsl"]),
        .init(group: .notchcast(feature: .screenshot), LocalizedStringResource("Screenshots", table: "Notchcast"), keywords: ["screen capture", "image"]),
        .init(group: .notchcast(feature: .screenText), LocalizedStringResource("Capture Text", table: "Notchcast"), keywords: ["ocr", "recognize", "barcode", "qr"]),
        .init(group: .notchcast(feature: .screenText), LocalizedStringResource("Remove line breaks", table: "Notchcast")),
        .init(group: .notchcast(feature: .scrollingCapture), LocalizedStringResource("Scrolling Capture", table: "Notchcast"), keywords: ["stitch", "screenshot"]),
        .init(group: .notchcast(feature: .dictationEnglish), LocalizedStringResource("Dictate in English", table: "Notchcast"), keywords: ["Globe", "translate"]),
        .init(group: .notchcast(feature: .globeDictation), LocalizedStringResource("Globe Dictation", table: "Notchcast"), keywords: ["fn", "microphone", "hold to talk"]),
        .init(group: .notchcast(feature: .screenshot), LocalizedStringResource("Screenshot destination", table: "Notchcast"), keywords: ["clipboard", "file", "save"]),
        .init(group: .notchcast(feature: .screenshot), LocalizedStringResource("Screenshot folder", table: "Notchcast"), keywords: ["directory", "desktop"]),
        .init(group: .notchcast(feature: .dictationCleanup), LocalizedStringResource("AI cleanup", table: "Notchcast")),
        .init(group: .notchcast(feature: .dictationHistory), LocalizedStringResource("Keep dictation history", table: "Notchcast")),
        .init(group: .notchcast(feature: .dictationHistory), "Clear History"),
        .init(group: .notchcast(feature: .dictationCleanup), LocalizedStringResource("Cleanup endpoint", table: "Notchcast")),
        .init(group: .notchcast(feature: .dictationCleanup), LocalizedStringResource("Cleanup effort", table: "Notchcast")),
        .init(group: .notchcast(feature: .dictationCleanup), LocalizedStringResource("Cleanup prompt addition", table: "Notchcast")),
        .init(group: .notchcast(feature: .dictationCleanup), LocalizedStringResource("Cleanup vocabulary", table: "Notchcast")),
        .init(group: .notchcast(feature: .dictationCleanup), LocalizedStringResource("Cleanup API key", table: "Notchcast")),
        .init(group: .notchcast(feature: .displayBrightness), LocalizedStringResource("Display Brightness", table: "Notchcast"), keywords: ["display", "dimming", "slider"]),
        .init(group: .notchcast(feature: .editorSpellChecking), LocalizedStringResource("Editor Spell Checking", table: "Notchcast"), keywords: ["editor", "spelling", "notes"]),
        .init(group: .notchcast(feature: .volumeLevels), LocalizedStringResource("Volume in Island", table: "Notchcast"), keywords: ["sound", "microphone", "mute"]),
        .init(group: .notchcast(feature: .systemNotices), LocalizedStringResource("System Notices", table: "Notchcast"), keywords: ["wifi", "tailscale", "battery"]),
        .init(group: .notchcast(feature: .lowDiskWarning), LocalizedStringResource("Low Disk Warning", table: "Notchcast"), keywords: ["storage", "warning"]),
        .init(group: .notchcast(feature: .quitProtection), LocalizedStringResource("Quit Protection", table: "Notchcast"), keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(group: .notchcast(feature: .agentActions), LocalizedStringResource("Agent access", table: "Notchcast")),
        .init(group: .notchcast(feature: .agentCLI), LocalizedStringResource("Command line tool", table: "Notchcast")),
        .init(group: .notchcast(feature: .liveTimers), LocalizedStringResource("Timers", table: "Notchcast"), keywords: ["duration", "alarm", "sound"]),
        .init(group: .notchcast(feature: .dayCalendar), "Calendar", keywords: ["events", "day", "schedule"]),
        .init(group: .notchcast(feature: .convertFiles), LocalizedStringResource("Convert Files", table: "Notchcast"), keywords: ["convert", "pdf", "formats"]),
        .init(group: .notchcast(feature: .mediaTools), LocalizedStringResource("Media Tools", table: "Notchcast"), keywords: ["compress", "gif", "resize", "text"]),
        .init(group: .notchcast(feature: .greenMaximize), LocalizedStringResource("Green Button Maximizes", table: "Notchcast"), keywords: ["window", "maximize", "restore"]),
        .init(group: .notchcast(feature: .middleClick), LocalizedStringResource("Trackpad Middle Click", table: "Notchcast"), keywords: ["three finger", "mouse", "trackpad"]),
        .init(group: .notchcast(feature: .showDesktop), LocalizedStringResource("Show Desktop with F3", table: "Notchcast"), keywords: ["mission control", "windows"]),
        .init(group: .notchcast(feature: .hideCommandM), LocalizedStringResource("Hide with ⌘M", table: "Notchcast"), keywords: ["minimize", "command m"]),
        .init(group: .notchcast(feature: .spacesOrder), LocalizedStringResource("Keep Spaces in a fixed order", table: "Notchcast"), keywords: ["desktop", "reorder"]),
        .init(group: .notchcast(feature: .greenMaximize), LocalizedStringResource("Excluded app bundle IDs (comma-separated)", table: "Notchcast"), keywords: ["green button", "maximize", "exceptions"]),
        .init(group: .notchcast(feature: .settingsBackup), LocalizedStringResource("Settings Backup", table: "Notchcast"), keywords: ["backup", "preferences", "daily"]),
        .init(group: .notchcast(feature: .startupItems), LocalizedStringResource("Startup Items", table: "Notchcast"), keywords: ["launchagents"]),
        .init(group: .notchcast(feature: .notificationCleanup), LocalizedStringResource("Notification Cleanup", table: "Notchcast"), keywords: ["disk", "ejection"]),
        .init(group: .notchcast(feature: .sudoTouchID), LocalizedStringResource("Touch ID for sudo", table: "Notchcast"), keywords: ["authentication"]),
        .init(group: .notchcast(feature: .spotlightOff), LocalizedStringResource("Spotlight Indexing Off", table: "Notchcast"), keywords: ["search"]),
        .init(group: .notchcast(feature: .downloads), LocalizedStringResource("Downloads", table: "Notchcast"), keywords: ["video", "audio", "transcript", "webpage", "clipboard"]),
        .init(group: .notchcast(feature: .downloadsAria2), LocalizedStringResource("Fast Downloads with aria2c", table: "Notchcast"), keywords: ["download", "speed", "aria2"]),
        .init(group: .notchcast(feature: .distill), LocalizedStringResource("Distill", table: "Notchcast"), keywords: ["links", "transcribe", "media", "queue"]),
        .init(group: .notchcast(feature: .distillTimestamps), LocalizedStringResource("Distill Timestamps", table: "Notchcast"), keywords: ["transcript", "time", "chunks"]),
        .init(group: .notchcast(feature: .distillConvert), LocalizedStringResource("Convert Distill Folder", table: "Notchcast"), keywords: ["markdown", "pdf", "ocr", "files"]),
        .init(group: .notchcast(feature: .machLink), LocalizedStringResource("Mac Link", table: "Notchcast"), keywords: ["pair", "network"]),
        .init(group: .notchcast(feature: .clearNotifications), LocalizedStringResource("Clear Notifications", table: "Notchcast"), keywords: ["notification center", "accessibility"]),
        .init(group: .notchcast(feature: .copyPath), "Copy Path", keywords: ["finder", "browser", "document", "link"]),
        .init(group: .notchcast(feature: .smallCommands), LocalizedStringResource("Small Commands", table: "Notchcast"), keywords: ["password", "shorten", "noise", "airdrop"]),
        .init(group: .notchcast(feature: .shelfBetweenMacs), LocalizedStringResource("Shelf between Macs", table: "Notchcast"), keywords: ["send", "files", "text"]),
        .init(group: .notchcast(feature: .linkHealth), LocalizedStringResource("Link Health", table: "Notchcast"), keywords: ["connection", "latency", "peer"]),
        .init(group: .notchcast(feature: .backupStatus), LocalizedStringResource("Backup Status", table: "Notchcast"), keywords: ["backup", "stale", "failure", "restore"]),
        .init(group: .notchcast(feature: .machRemote), LocalizedStringResource("Remote Mac", table: "Notchcast"), keywords: ["ssh", "terminal", "Remote Mac address"]),
        .init(group: .notchcast(feature: .sendFiles), LocalizedStringResource("Send to Remote Mac", table: "Notchcast"), keywords: ["files", "Finder"]),
        .init(group: .notchcast(feature: .updateRemote), LocalizedStringResource("Update Remote Mac", table: "Notchcast"), keywords: ["update", "ssh"]),
        .init(group: .notchcast(feature: .machRemote), LocalizedStringResource("Remote Mac address", table: "Notchcast"), keywords: ["ssh", "host", "alias"]),
        .init(group: .notchcast(feature: .machRemote), LocalizedStringResource("Remote terminal directory", table: "Notchcast")),
        .init(group: .notchcast(feature: .machRemote), LocalizedStringResource("Remote update script path", table: "Notchcast")),
        .init(group: .notchcast(feature: .backupStatus), LocalizedStringResource("Backup status file path", table: "Notchcast")),
        .init(group: .notchcast(feature: .machLink), LocalizedStringResource("Pairing code", table: "Notchcast"), keywords: ["pair", "unpair"]),
        .init(group: .notchcast(feature: .musicNowPlaying), LocalizedStringResource("Show what is playing", table: "Notchcast"), keywords: ["now playing", "track", "cover", "media", "song"]),
        .init(group: .notchcast(feature: .musicLastPlayer), LocalizedStringResource("Resume last player", table: "Notchcast"), keywords: ["play key", "spotify", "media key"]),
        .init(group: .notchcast(feature: .musicBlockAppleMusic), LocalizedStringResource("Stop Apple Music opening on media keys", table: "Notchcast"), keywords: ["music app", "itunes", "media key", "play key"]),
        .init(group: .notchcast(feature: .musicSharpCovers), LocalizedStringResource("Find sharp covers for Firefox and Zen", table: "Notchcast"), keywords: ["artwork", "album art", "youtube", "browser"]),
        .init(group: .notchcast(feature: .spotifyConnect), LocalizedStringResource("Spotify Connect speaker", table: "Notchcast"), keywords: ["soloist", "spotify", "speaker", "connect", "phone"]),
        .init(group: .notchcast(feature: .spotifyConnect), "API key", keywords: ["soloist", "key", "developer"]),
        .init(group: .notchcast(feature: .spotifyConnect), LocalizedStringResource("Device name", table: "Notchcast"), keywords: ["soloist", "speaker name"]),
        .init(group: .notchcast(feature: .spotifyConnect), LocalizedStringResource("Download Soloist", table: "Notchcast"), keywords: ["soloist", "update", "build", "expiry"]),
        .init(group: .notchcast(feature: .microphoneMute), LocalizedStringResource("Microphone mute", table: "Notchcast"), keywords: ["mute", "f5", "mic"]),
        .init(group: .notchcast(feature: .torrents), LocalizedStringResource("Torrents", table: "Notchcast"), keywords: ["magnet", "torrent", "download"]),
        .init(group: .notchcast(feature: .torrentsUseIPhone), LocalizedStringResource("Use a plugged-in iPhone for big downloads", table: "Notchcast"), keywords: ["wifi", "iphone", "usb", "hotspot", "network"]),
        .init(group: .notchcast(feature: .torrentsKeepSharing), LocalizedStringResource("Keep sharing until ratio 1.0", table: "Notchcast"), keywords: ["seed", "seeding", "upload"]),
        .init(group: .notchcast(feature: .torrents), LocalizedStringResource("aria2c", table: "Notchcast"), keywords: ["install", "homebrew", "tool", "path"]),
        .init(group: .notchcast(feature: .pastePlain), LocalizedStringResource("Paste Plain Text", table: "Notchcast"), keywords: ["hyper", "clipboard", "formatting"]),
        .init(group: .notchcast(feature: .finderCutPaste), LocalizedStringResource("Finder Cut and Paste", table: "Notchcast"), keywords: ["files", "move", "clipboard"]),
        .init(group: .notchcast(feature: .finderRename), LocalizedStringResource("Finder Rename", table: "Notchcast"), keywords: ["hyper", "shortcut", "return"]),
        .init(group: .notchcast(feature: .finderCutPaste), LocalizedStringResource("Cut and move files", table: "Notchcast"), keywords: ["copy", "escape", "cancel"]),
        .init(group: .notchcast(feature: .finderRename), LocalizedStringResource("Rename selection", table: "Notchcast"), keywords: ["hyper", "shortcut", "return"]),
        .init(group: .notchcast(feature: .pasteImage), LocalizedStringResource("Paste Image in Finder", table: "Notchcast"), keywords: ["png", "clipboard", "file"]),
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
