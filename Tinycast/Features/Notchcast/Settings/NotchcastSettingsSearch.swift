import Foundation

/// One line per anchor and per entry, so branches that add rows merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension SettingsAnchor {
    static let notchcastAppearance = Self(tab: .notchcast, title: "Appearance")
    static let notchcastClean = Self(tab: .notchcast, title: "Clean")
    static let notchcastCleaning = Self(tab: .notchcast, title: "Cleaning mode")
    static let notchcastAppUpdates = Self(tab: .notchcast, title: "App updates")
    static let notchcastMacUpdate = Self(tab: .notchcast, title: "Update this Mac")
    static let notchcastTweaksApps = Self(tab: .notchcast, title: "System preferences")
    static let notchcastTasks = Self(tab: .notchcast, title: "Tasks")
    static let notchcastArchives = Self(tab: .notchcast, title: "Archives")
    static let notchcastBuildStats = Self(tab: .notchcast, title: "Build statistics")
    static let notchcastAlerts = Self(tab: .notchcast, title: LocalizedStringResource("Monitor Alerts"))
    static let notchcastAlertCPU = Self(tab: .notchcast, title: "CPU usage threshold")
    static let notchcastAlertTemperature = Self(tab: .notchcast, title: "CPU temperature threshold")
    static let notchcastAlertMemory = Self(tab: .notchcast, title: "Memory pressure threshold")
    static let notchcastAlertDisk = Self(tab: .notchcast, title: "Disk free threshold")
    static let notchcastAlertBattery = Self(tab: .notchcast, title: "Battery threshold")
    static let notchcastAlertBatteryTemperature = Self(tab: .notchcast, title: "Battery temperature threshold")
    static let notchcastAccessories = Self(tab: .notchcast, title: "Accessory batteries")
    static let notchcastChargePercent = Self(tab: .notchcast, title: "Charge limit percent")
    static let notchcastAwakeDuration = Self(tab: .notchcast, title: "Keep-awake duration")
    static let notchcastMonitor = Self(tab: .notchcast, title: LocalizedStringResource("System Monitor"))
    static let notchcastFanMode = Self(tab: .notchcast, title: "Fan mode")
    static let notchcastIsland = Self(tab: .notchcast, title: "Island")
    static let notchcastOptions = Self(tab: .notchcast, title: LocalizedStringResource("Island Options"))
    static let notchcastLauncher = Self(tab: .notchcast, title: "Launcher")
    static let notchcastSystem = Self(tab: .notchcast, title: "System")
    static let notchcastActivities = Self(tab: .notchcast, title: "Activities")
    static let notchcastMusic = Self(tab: .notchcast, title: "Music")
    // ai-design-check-ignore-next-line sentence-case -- Spotify Connect is a product name.
    static let notchcastSpotify = Self(tab: .notchcast, title: "Spotify Connect")
    static let notchcastMicrophone = Self(tab: .notchcast, title: "Microphone")
    static let notchcastPermissions = Self(tab: .notchcast, title: "Permissions")
    static let notchcastShortcuts = Self(tab: .notchcast, title: LocalizedStringResource("Global Shortcuts"))
    static let notchcastBrightness = Self(tab: .notchcast, title: "Brightness")
    static let notchcastQuitProtection = Self(tab: .notchcast, title: LocalizedStringResource("Quit Protection"))
    static let notchcastTimers = Self(tab: .notchcast, title: "Timers")
    static let notchcastDay = Self(tab: .notchcast, title: "Day")
    static let notchcastTweaks = Self(tab: .notchcast, title: "Tweaks")
    static let notchcastDownloads = Self(tab: .notchcast, title: "Downloads")
    static let notchcastLauncherTools = Self(tab: .notchcast, title: "Launcher tools")
    static let notchcastAIUsage = Self(tab: .notchcast, title: "Mac link")
    static let notchcastTorrents = Self(tab: .notchcast, title: "Torrents")
    static let notchcastPaste = Self(tab: .notchcast, title: "Clipboard")
    static let notchcastRemoteMac = Self(tab: .notchcast, title: LocalizedStringResource("Remote Mac"))
    static let notchcastFinder = Self(tab: .notchcast, title: "Finder")
    static let notchcastCaptureAndDictation = Self(tab: .notchcast, title: "Capture and dictation")
}

extension SettingsSearchCatalog {
    /// Row titles match `NotchcastFeature.title`, which the pane's rows show.
    static let notchcast: [SettingsSearchEntry] = [
        .init(.notchcastSystem, "Audio device priority", keywords: ["sound", "outputs", "microphones"]),
        .init(.notchcastClean, "Junk", keywords: ["trash", "cache"]),
        .init(.notchcastClean, "Clean history", keywords: ["restore", "runs"]),
        .init(.notchcastClean, "AI data", keywords: ["claude", "codex", "opencode"]),
        .init(.notchcastClean, "Disk analyzer", keywords: ["folder", "size"]),
        .init(.notchcastClean, "Project purge", keywords: ["projects", "build", "artifacts"]),
        .init(.notchcastClean, "Optimize", keywords: ["quick look", "download history", "open with"]),
        .init(.notchcastCleaning, "Cleaning mode"),
        .init(.notchcastAppUpdates, "App updates"),
        .init(.notchcastMacUpdate, "Update this Mac"),
        .init(group: .notchcastTasks, "Tasks", keywords: ["todo", "task store", "local tasks"]),
        .init(group: .notchcastTasks, "Import Todoist JSON export…", keywords: ["json", "local file", "import"]),
        .init(.notchcastSystem, "URL cleaner", keywords: ["tracking", "clipboard", "parameters"]),
        .init(.notchcastAppearance, "Custom appearance", keywords: ["enable", "colours", "colors", "theme"]),
        .init(.notchcastAppearance, "Surface", keywords: ["glass", "black", "matte", "material"]),
        .init(.notchcastAppearance, "Light theme", keywords: ["palette", "raycast", "ray.so"]),
        .init(.notchcastAppearance, "Dark theme", keywords: ["palette", "raycast", "ray.so"]),
        .init(.notchcastAppearance, "Theme backdrop", keywords: ["opacity", "background", "transparency"]),
        .init(.notchcastAppearance, "Import from link", keywords: ["theme", "raycast", "ray.so", "url"]),
        .init(.notchcastArchives, "Archives", keywords: ["extract", "zip", "7z", "rar", "tar", "tgz", "001", "hatchzip"]),
        .init(.notchcastArchives, "Extract in place", keywords: ["shrink", "space", "destructive"]),
        .init(.notchcastArchives, "Open archives with Notchcast", keywords: ["default", "handler", "Archive Utility"]),
        .init(.notchcastAlerts, "Monitor Alerts"),
        .init(.notchcastAlertCPU, "CPU usage threshold"),
        .init(.notchcastAlertTemperature, "CPU temperature threshold"),
        .init(.notchcastAlertMemory, "Memory pressure threshold"),
        .init(.notchcastAlertDisk, "Disk free threshold"),
        .init(.notchcastAlertBattery, "Battery threshold"),
        .init(.notchcastAlertBatteryTemperature, "Battery temperature threshold"),
        .init(pane: .notchcast, keywords: ["notch", "island", "dynamic island"]),
        .init(.notchcastTweaksApps, "Disable autocorrect"),
        .init(.notchcastTweaksApps, "Disable smart punctuation"),
        .init(.notchcastTweaksApps, "Disable double-space period"),
        .init(.notchcastTweaksApps, "Disable auto-capitalization"),
        .init(.notchcastTweaksApps, "Enable key repeat"),
        .init(.notchcastTweaksApps, "Show file extensions"),
        .init(.notchcastTweaksApps, "Show hidden files"),
        .init(.notchcastTweaksApps, "Show path bar"),
        .init(.notchcastTweaksApps, "Show status bar"),
        .init(.notchcastTweaksApps, "Keep folders first"),
        .init(.notchcastTweaksApps, "Search current folder"),
        .init(.notchcastTweaksApps, "Disable extension warning"),
        .init(.notchcastTweaksApps, "Show path in title"),
        .init(.notchcastTweaksApps, "Avoid network metadata"),
        .init(.notchcastTweaksApps, "Remove trash after 30 days"),
        .init(.notchcastTweaksApps, "Save locally"),
        .init(.notchcastTweaksApps, "Expand save dialogs"),
        .init(.notchcastTweaksApps, "Use list view"),
        .init(.notchcastTweaksApps, "Avoid USB metadata"),
        .init(.notchcastTweaksApps, "Hide desktop disks"),
        .init(.notchcastTweaksApps, "Hide recent apps"),
        .init(.notchcastTweaksApps, "Remove auto-hide delay"),
        .init(.notchcastTweaksApps, "Disable launch animation"),
        .init(.notchcastTweaksApps, "Minimize into app"),
        .init(.notchcastTweaksApps, "Disable window animations"),
        .init(.notchcastTweaksApps, "Remove tiled window margins"),
        .init(.notchcastTweaksApps, "Remove screenshot shadow"),
        .init(.notchcastTweaksApps, "Disable click to desktop"),
        .init(.notchcastTweaksApps, "Hide desktop widgets"),
        .init(.notchcastTweaksApps, "Typing"),
        .init(.notchcastTweaksApps, "Show library"),
        .init(.notchcastTweaksApps, "Restrict gaming"),
        .init(.notchcastTweaksApps, "Restrict iPhone mirroring"),
        .init(.notchcastTweaksApps, "Restrict music service"),
        .init(.notchcastTweaksApps, "Restrict book store"),
        .init(.notchcastTweaksApps, "Finder"),
        .init(.notchcastTweaksApps, "Dock and windows"),
        .init(.notchcastTweaksApps, "Apple apps"),
        .init(.notchcastTweaksApps, "iPhone backup"),
        .init(.notchcastTweaksApps, "Key repeat speed"),
        .init(.notchcastTweaksApps, "Key repeat delay"),
        .init(.notchcastTweaksApps, "New Finder windows"),
        .init(.notchcastTweaksApps, "Turn off iPhone auto backups"),
        .init(.notchcastTweaksApps, "iPhone backup folder"),
        .init(.notchcastIsland, "Island", keywords: ["notch", "enable", "dynamic island"]),
        .init(.notchcastOptions, "External Displays", keywords: ["monitor", "screen", "display", "hover delay"]),
        .init(.notchcastOptions, "Full-Screen Apps", keywords: ["fullscreen", "full screen", "video"]),
        .init(.notchcastOptions, "Open on Hover", keywords: ["pointer", "mouse", "hover"]),
        .init(.notchcastOptions, "Status Messages", keywords: ["hud", "toast", "message"]),
        .init(.notchcastOptions, "Live Activities", keywords: ["now playing", "timer", "activity"]),
        .init(.notchcastLauncher, "Launcher from Island", keywords: ["palette", "search", "open"]),
        .init(.notchcastLauncher, "Launcher Number Keys", keywords: ["command", "results", "1", "9"]),
        .init(.notchcastLauncher, "Alias and Space", keywords: ["alias", "space", "arguments"]),
        .init(.notchcastLauncher, "Quick Look on Space", keywords: ["file", "preview", "markdown"]),
        .init(.notchcastMonitor, "System Monitor", keywords: ["cpu", "memory", "temperature"]),
        .init(.notchcastMonitor, "Fan Control", keywords: ["cooling", "rpm"]),
        .init(.notchcastAccessories, "Accessory batteries", keywords: ["bluetooth", "charging", "mouse", "keyboard"]),
        .init(.notchcastFanMode, "Fan mode"),
        .init(.notchcastMonitor, "Charge Limit"),
        .init(.notchcastMonitor, "Battery Sailing"),
        .init(.notchcastMonitor, "Battery Heat Protection"),
        .init(.notchcastMonitor, "Battery Calibration"),
        .init(.notchcastMonitor, "Keep Awake"),
        .init(.notchcastMonitor, "Keep Awake with Lid Closed"),
        .init(.notchcastChargePercent, "Charge limit percent"),
        .init(.notchcastAwakeDuration, "Keep-awake duration"),
        .init(group: .notchcastShortcuts, "Toggle Island"),
        .init(.notchcastCaptureAndDictation, "Color Picker", keywords: ["colour", "eyedropper", "sample"]),
        .init(.notchcastCaptureAndDictation, "Color format", keywords: ["colour", "hex", "rgb", "hsl"]),
        .init(.notchcastCaptureAndDictation, "Screenshots", keywords: ["screen capture", "image"]),
        .init(.notchcastCaptureAndDictation, "Capture Text", keywords: ["ocr", "recognize", "barcode", "qr"]),
        .init(.notchcastCaptureAndDictation, "Remove line breaks"),
        .init(.notchcastCaptureAndDictation, "Scrolling Capture", keywords: ["stitch", "screenshot"]),
        .init(.notchcastCaptureAndDictation, "Dictate in English", keywords: ["Globe", "translate"]),
        .init(.notchcastCaptureAndDictation, "Globe Dictation", keywords: ["fn", "microphone", "hold to talk"]),
        .init(.notchcastCaptureAndDictation, "Screenshot destination", keywords: ["clipboard", "file", "save"]),
        .init(.notchcastCaptureAndDictation, "Screenshot folder", keywords: ["directory", "desktop"]),
        .init(.notchcastCaptureAndDictation, "AI cleanup"),
        .init(.notchcastCaptureAndDictation, "Keep dictation history"),
        .init(.notchcastCaptureAndDictation, "Delete history"),
        .init(.notchcastCaptureAndDictation, "Cleanup endpoint"),
        .init(.notchcastCaptureAndDictation, "Cleanup effort"),
        .init(.notchcastCaptureAndDictation, "Cleanup prompt addition"),
        .init(.notchcastCaptureAndDictation, "Cleanup vocabulary"),
        .init(.notchcastCaptureAndDictation, "Cleanup API key"),
        .init(.notchcastSystem, "Display Brightness", keywords: ["display", "dimming", "slider"]),
        .init(.notchcastSystem, "Editor Spell Checking", keywords: ["editor", "spelling", "notes"]),
        .init(.notchcastSystem, "Volume in Island", keywords: ["sound", "microphone", "mute"]),
        .init(.notchcastSystem, "System Notices", keywords: ["wifi", "tailscale", "battery"]),
        .init(.notchcastSystem, "Low Disk Warning", keywords: ["storage", "warning"]),
        .init(.notchcastSystem, "Quit Protection", keywords: ["quit", "hold", "double press", "exceptions"]),
        .init(.notchcastSystem, "Agent access"),
        .init(.notchcastSystem, "Command line tool"),
        .init(.notchcastActivities, "Timers", keywords: ["duration", "alarm", "sound"]),
        .init(.notchcastActivities, "Calendar", keywords: ["events", "day", "schedule"]),
        .init(.notchcastActivities, "Convert Files", keywords: ["convert", "pdf", "formats"]),
        .init(.notchcastActivities, "Media Tools", keywords: ["compress", "gif", "resize", "text"]),
        .init(.notchcastLauncher, "Command Runner", keywords: ["catalogue", "shell", "tasks"]),
        .init(.notchcastSystem, "Green Button Maximizes", keywords: ["window", "maximize", "restore"]),
        .init(.notchcastSystem, "Trackpad Middle Click", keywords: ["three finger", "mouse", "trackpad"]),
        .init(.notchcastSystem, "Show Desktop with F3", keywords: ["mission control", "windows"]),
        .init(.notchcastSystem, "Hide with ⌘M", keywords: ["minimize", "command m"]),
        .init(.notchcastSystem, "Keep Spaces in a fixed order", keywords: ["desktop", "reorder"]),
        .init(.notchcastSystem, "Excluded app bundle IDs (comma-separated)", keywords: ["green button", "maximize", "exceptions"]),
        .init(.notchcastSystem, "Settings Backup", keywords: ["backup", "preferences", "daily"]),
        .init(.notchcastTweaks, "Startup Items", keywords: ["launchagents"]),
        .init(.notchcastTweaks, "Notification Cleanup", keywords: ["disk", "ejection"]),
        .init(.notchcastTweaks, "Touch ID for sudo", keywords: ["authentication"]),
        .init(.notchcastTweaks, "Spotlight Indexing Off", keywords: ["search"]),
        .init(.notchcastActivities, "Downloads", keywords: ["video", "audio", "transcript", "webpage", "clipboard"]),
        .init(.notchcastActivities, "Fast Downloads with aria2c", keywords: ["download", "speed", "aria2"]),
        .init(.notchcastActivities, "Distill", keywords: ["links", "transcribe", "media", "queue"]),
        .init(.notchcastActivities, "Distill Timestamps", keywords: ["transcript", "time", "chunks"]),
        .init(.notchcastActivities, "Convert Distill Folder", keywords: ["markdown", "pdf", "ocr", "files"]),
        .init(.notchcastSystem, "Mac Link", keywords: ["pair", "network"]),
        .init(.notchcastLauncher, "Clear Notifications", keywords: ["notification center", "accessibility"]),
        .init(.notchcastLauncher, "Copy Path", keywords: ["finder", "browser", "document", "link"]),
        .init(.notchcastLauncher, "Small Commands", keywords: ["password", "shorten", "noise", "airdrop"]),
        .init(.notchcastActivities, "Shelf between Macs", keywords: ["send", "files", "text"]),
        .init(.notchcastSystem, "Link Health", keywords: ["connection", "latency", "peer"]),
        .init(.notchcastSystem, "Backup Status", keywords: ["backup", "stale", "failure", "restore"]),
        .init(.notchcastSystem, "Remote Mac", keywords: ["ssh", "terminal", "Remote Mac address"]),
        .init(.notchcastSystem, "Send to Remote Mac", keywords: ["files", "Finder"]),
        .init(.notchcastSystem, "Update Remote Mac", keywords: ["update", "ssh"]),
        .init(.notchcastRemoteMac, "Remote Mac address", keywords: ["ssh", "host", "alias"]),
        .init(.notchcastRemoteMac, "Remote terminal directory"),
        .init(.notchcastRemoteMac, "Remote update script path"),
        .init(.notchcastSystem, "Backup status file path"),
        .init(.notchcastActivities, "AI usage cache directory"),
        .init(group: .notchcastAIUsage, "Pairing code", keywords: ["pair", "unpair"]),
        .init(.notchcastMusic, "Show what is playing", keywords: ["now playing", "track", "cover", "media", "song"]),
        .init(.notchcastMusic, "Resume last player", keywords: ["play key", "spotify", "media key"]),
        .init(.notchcastMusic, "Stop Apple Music opening on media keys", keywords: ["music app", "itunes", "media key", "play key"]),
        .init(.notchcastSpotify, "Spotify Connect speaker", keywords: ["soloist", "spotify", "speaker", "connect", "phone"]),
        .init(.notchcastSpotify, "API key", keywords: ["soloist", "key", "developer"]),
        .init(.notchcastSpotify, "Device name", keywords: ["soloist", "speaker name"]),
        .init(group: .notchcastSpotify, "Download Soloist", keywords: ["soloist", "update", "build", "expiry"]),
        .init(.notchcastMicrophone, "Microphone mute", keywords: ["mute", "f5", "mic"]),
        .init(.notchcastTorrents, "Torrents", keywords: ["magnet", "torrent", "download"]),
        .init(.notchcastTorrents, "Use a plugged-in iPhone for big downloads", keywords: ["wifi", "iphone", "usb", "hotspot", "network"]),
        .init(.notchcastTorrents, "Keep sharing until ratio 1.0", keywords: ["seed", "seeding", "upload"]),
        .init(.notchcastTorrents, "aria2c", keywords: ["install", "homebrew", "tool", "path"]),
        .init(.notchcastPaste, "Paste Plain Text", keywords: ["hyper", "clipboard", "formatting"]),
        .init(.notchcastFinder, "Finder Cut and Paste", keywords: ["files", "move", "clipboard"]),
        .init(.notchcastFinder, "Finder Rename", keywords: ["hyper", "shortcut", "return"]),
        .init(.notchcastFinder, "Cut and move files", keywords: ["copy", "escape", "cancel"]),
        .init(.notchcastFinder, "Rename selection", keywords: ["hyper", "shortcut", "return"]),
        .init(.notchcastPaste, "Paste Image in Finder", keywords: ["png", "clipboard", "file"]),
    ]
}
