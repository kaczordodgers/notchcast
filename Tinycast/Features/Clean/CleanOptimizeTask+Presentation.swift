import Foundation

extension CleanOptimizeTask {
    var title: String {
        switch self {
        case .quickLook: String(localized: "Reset Quick Look cache")
        case .downloadHistory: String(localized: "Clear download history")
        case .openWithMenu: String(localized: "Rebuild open with menu")
        }
    }

    var question: String {
        switch self {
        case .quickLook: String(localized: "Reset the Quick Look cache (size unknown)?")
        case .downloadHistory: String(localized: "Clear download history (size unknown)?")
        case .openWithMenu: String(localized: "Rebuild the Open With menu (size unknown)?")
        }
    }
}
