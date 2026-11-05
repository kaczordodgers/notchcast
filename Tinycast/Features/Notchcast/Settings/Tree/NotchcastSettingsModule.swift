import Foundation

enum NotchcastSettingsModule: String, CaseIterable, Sendable {
    case island
    case launcher
    case musicAndSound = "music-and-sound"
    case dayAndTasks = "day-and-tasks"
    case monitorAndFans = "monitor-and-fans"
    case battery
    case windowsAndDisplay = "windows-and-display"
    case downloads
    case filesAndClipboard = "files-and-clipboard"
    case capture
    case dictation
    case aiAndAgents = "ai-and-agents"
    case twoMacs = "two-macs"
    case backups
    case cleanAndUpdates = "clean-and-updates"
    case tweaks
    case privacyAndStartup = "privacy-and-startup"

    var title: String {
        switch self {
        case .island: String(localized: "Island", table: "Notchcast")
        case .launcher: String(localized: "Launcher")
        case .musicAndSound: String(localized: "Music and Sound", table: "Notchcast")
        case .dayAndTasks: String(localized: "Day and Tasks", table: "Notchcast")
        case .monitorAndFans: String(localized: "Monitor and Fans", table: "Notchcast")
        case .battery: String(localized: "Battery", table: "Notchcast")
        case .windowsAndDisplay: String(localized: "Windows and Display", table: "Notchcast")
        case .downloads: String(localized: "Downloads", table: "Notchcast")
        case .filesAndClipboard: String(localized: "Files and Clipboard", table: "Notchcast")
        case .capture: String(localized: "Capture", table: "Notchcast")
        case .dictation: String(localized: "Dictation")
        case .aiAndAgents: String(localized: "AI and Agents", table: "Notchcast")
        case .twoMacs: String(localized: "Two Macs", table: "Notchcast")
        case .backups: String(localized: "Backups", table: "Notchcast")
        case .cleanAndUpdates: String(localized: "Clean and Updates", table: "Notchcast")
        case .tweaks: String(localized: "Tweaks", table: "Notchcast")
        case .privacyAndStartup: String(localized: "Privacy and Startup", table: "Notchcast")
        }
    }

    var systemImage: String {
        switch self {
        case .island: "macbook.gen2"
        case .launcher: "magnifyingglass"
        case .musicAndSound: "music.note"
        case .dayAndTasks: "calendar"
        case .monitorAndFans: "gauge.with.dots.needle.50percent"
        case .battery: "battery.100percent"
        case .windowsAndDisplay: "macwindow"
        case .downloads: "arrow.down.circle"
        case .filesAndClipboard: "doc.on.clipboard"
        case .capture: "camera"
        case .dictation: "waveform"
        case .aiAndAgents: "sparkles"
        case .twoMacs: "desktopcomputer"
        case .backups: "externaldrive"
        case .cleanAndUpdates: "sparkles.rectangle.stack"
        case .tweaks: "slider.horizontal.3"
        case .privacyAndStartup: "lock.shield"
        }
    }

    var tab: SettingsTab {
        switch self {
        case .island: .notchcast
        case .launcher: .notchcastLauncher
        case .musicAndSound: .notchcastMusicAndSound
        case .dayAndTasks: .notchcastDayAndTasks
        case .monitorAndFans: .notchcastMonitorAndFans
        case .battery: .notchcastBattery
        case .windowsAndDisplay: .notchcastWindowsAndDisplay
        case .downloads: .notchcastDownloads
        case .filesAndClipboard: .notchcastFilesAndClipboard
        case .capture: .notchcastCapture
        case .dictation: .notchcastDictation
        case .aiAndAgents: .notchcastAIAndAgents
        case .twoMacs: .notchcastTwoMacs
        case .backups: .notchcastBackups
        case .cleanAndUpdates: .notchcastCleanAndUpdates
        case .tweaks: .notchcastTweaks
        case .privacyAndStartup: .notchcastPrivacyAndStartup
        }
    }

    init?(tab: SettingsTab) {
        guard let module = Self.allCases.first(where: { $0.tab == tab }) else { return nil }
        self = module
    }

    var slug: String { self == .island ? "notchcast" : "notchcast-" + rawValue }

    /// A group whose switches are all hidden (not wired yet) shows no header either.
    var visibleGroups: [NotchcastSettingsGroup] {
        groups.filter { $0.items.contains { $0.feature?.isWired ?? true } }
    }

    static func module(of feature: NotchcastFeature) -> Self {
        Self.allCases.first { $0.groups.contains { $0.items.contains { $0.feature == feature } } }!
    }

    static func module(of setting: NotchcastSetting) -> Self {
        Self.allCases.first { $0.groups.contains { $0.items.contains { $0.settings.contains(setting) } } }!
    }
}
