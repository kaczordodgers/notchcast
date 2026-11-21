import Foundation

/// A Notchcast Settings section; an add-on picks one, `NotchcastPane` places it, empty ones hide.
enum NotchcastCategory: String, CaseIterable, Sendable {
    case capture
    case displaySound
    case keyboardMouse
    case launcher
    case filesDownloads
    case power
    case music
    case notices
    case betweenMacs
    case macTweaks
    case agents

    var title: String {
        switch self {
        case .capture: String(localized: "Capture", table: "Notchcast")
        case .displaySound: String(localized: "Display & Sound", table: "Notchcast")
        case .keyboardMouse: String(localized: "Keyboard & Mouse", table: "Notchcast")
        case .launcher: String(localized: "Launcher")
        case .filesDownloads: String(localized: "Downloads", table: "Notchcast")
        case .power: String(localized: "Power")
        case .music: String(localized: "Music", table: "Notchcast")
        case .notices: String(localized: "Notices", table: "Notchcast")
        case .betweenMacs: String(localized: "Between Macs", table: "Notchcast")
        case .macTweaks: String(localized: "Mac Tweaks", table: "Notchcast")
        case .agents: String(localized: "Agents", table: "Notchcast")
        }
    }
}
