import Foundation

extension NotchcastFeature {
    var isArchiveSetting: Bool {
        switch self {
        case .archives, .archivesInPlace, .archivesDefaultApp: true
        default: false
        }
    }
}
