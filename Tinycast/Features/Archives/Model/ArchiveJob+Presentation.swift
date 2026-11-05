import Foundation

extension ArchiveJob {
    var stateTitle: String {
        switch state {
        case .queued: String(localized: "Queued", table: "Notchcast")
        case .preflighting: String(localized: "Checking archive…", table: "Notchcast")
        case .extracting: String(localized: "Extracting…", table: "Notchcast")
        case .cancelling: String(localized: "Cancelling…", table: "Notchcast")
        case .finished: String(localized: "Finished", table: "Notchcast")
        case .failed: String(localized: "Failed", table: "Notchcast")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    var fallbackNote: String? {
        switch fallback {
        case .inPlaceCheckRefused: String(localized: "In-place extraction is unavailable; keeping the archive.", table: "Notchcast")
        case .resumingKeepArchive: String(localized: "Resuming extraction while keeping the archive.", table: "Notchcast")
        case nil:
            if state == .cancelled, effectiveMode == .inPlace {
                String(localized: "Try Again resumes in-place extraction.", table: "Notchcast")
            } else {
                nil
            }
        }
    }

    var canCancel: Bool { [.queued, .preflighting, .extracting].contains(state) }
    var canRetry: Bool { [.failed, .cancelled].contains(state) }
}
