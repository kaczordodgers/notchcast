import Foundation

extension MacUpdateService.State {
    var title: String {
        switch self {
        case .running: String(localized: "Running")
        case .skipped: String(localized: "Skipped")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}
