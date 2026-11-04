import Foundation

extension ArchiveJob {
    var stateTitle: String {
        switch state {
        case .queued: String(localized: "Queued")
        case .preflighting: String(localized: "Checking archive…")
        case .extracting: String(localized: "Extracting…")
        case .cancelling: String(localized: "Cancelling…")
        case .finished: String(localized: "Finished")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    var fallbackNote: String? {
        switch fallback {
        case .inPlaceCheckRefused: String(localized: "In-place extraction is unavailable; keeping the archive.")
        case .resumingKeepArchive: String(localized: "Resuming extraction while keeping the archive.")
        case nil:
            if state == .cancelled, effectiveMode == .inPlace {
                String(localized: "Try Again resumes in-place extraction.")
            } else {
                nil
            }
        }
    }

    var canCancel: Bool { [.queued, .preflighting, .extracting].contains(state) }
    var canRetry: Bool { [.failed, .cancelled].contains(state) }
}
