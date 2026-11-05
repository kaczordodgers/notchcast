import Foundation

enum TreadmillFailure: LocalizedError, Equatable, Sendable {
    case disabled, unavailable, notReady, alreadyWalking, noWalk, notPaused, notRunning
    case invalidSpeed, invalidMinutes, timedOut, padError(UInt8), invalidHistory

    var errorDescription: String? {
        switch self {
        case .disabled: String(localized: "Walking pad controls are turned off.", table: "Notchcast")
        case .unavailable: String(localized: "The walking pad is not connected.", table: "Notchcast")
        case .notReady: String(localized: "The walking pad is not ready.", table: "Notchcast")
        case .alreadyWalking: String(localized: "A walk is already in progress.", table: "Notchcast")
        case .noWalk: String(localized: "There is no walk in progress.", table: "Notchcast")
        case .notPaused: String(localized: "The walk is not paused.", table: "Notchcast")
        case .notRunning: String(localized: "The walk is not running.", table: "Notchcast")
        case .invalidSpeed: String(localized: "Choose a speed supported by the walking pad.", table: "Notchcast")
        case .invalidMinutes: String(localized: "Choose a valid walk duration.", table: "Notchcast")
        case .timedOut: String(localized: "The walking pad did not respond in time.", table: "Notchcast")
        case .padError: String(localized: "The walking pad reported an error.", table: "Notchcast")
        case .invalidHistory: String(localized: "The walk history could not be read.", table: "Notchcast")
        }
    }
}
