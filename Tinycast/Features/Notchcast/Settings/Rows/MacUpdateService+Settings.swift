import Foundation

extension MacUpdateService.State {
    var reason: String? {
        switch self {
        case .failed(let reason), .skipped(let reason):
            switch reason {
            case "missing-homebrew": String(localized: "Homebrew is not installed.", table: "Notchcast")
            case "missing-mas": String(localized: "The mas tool is not installed.", table: "Notchcast")
            case "missing-or-unsupported-cli-install": String(localized: "No supported command-line installation was found.", table: "Notchcast")
            case "homebrew-lock-timeout": String(localized: "Homebrew is busy. Try again later.", table: "Notchcast")
            case "timeout": String(localized: "The update timed out.", table: "Notchcast")
            case "quarantine-cleanup-failed": String(localized: "The updated app could not be cleared to open.", table: "Notchcast")
            default: reason
            }
        default: nil
        }
    }

    var title: String {
        switch self {
        case .running: String(localized: "Running")
        case .skipped: String(localized: "Skipped", table: "Notchcast")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Failed", table: "Notchcast")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}
