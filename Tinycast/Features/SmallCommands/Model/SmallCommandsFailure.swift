import Foundation

enum SmallCommandsFailure: LocalizedError, Equatable, Sendable {
    case disabled
    case noLink
    case controlCenterNotRunning
    case noAirPods
    case noiseControlUnchanged
    case airDropCancelled
    case nothingSelected
    case airDropUnavailable

    var errorDescription: String? {
        switch self {
        case .disabled: String(localized: "Unavailable")
        case .noLink: String(localized: "No link to shorten.", table: "Notchcast")
        case .controlCenterNotRunning: String(localized: "Control Center is not running.", table: "Notchcast")
        case .noAirPods: String(localized: "No AirPods with noise control found.", table: "Notchcast")
        case .noiseControlUnchanged: String(localized: "Noise control did not change.", table: "Notchcast")
        case .airDropCancelled: String(localized: "AirDrop was cancelled.", table: "Notchcast")
        case .nothingSelected: String(localized: "Select files in Finder first.", table: "Notchcast")
        case .airDropUnavailable: String(localized: "AirDrop is unavailable.", table: "Notchcast")
        }
    }
}
