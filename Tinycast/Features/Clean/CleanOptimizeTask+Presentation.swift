import Foundation

extension CleanOptimizeTask {
    var title: String {
        switch self {
        case .quickLook: String(localized: "Reset Quick Look cache", table: "Notchcast")
        case .downloadHistory: String(localized: "Clear download history", table: "Notchcast")
        case .openWithMenu: String(localized: "Rebuild open with menu", table: "Notchcast")
        }
    }

    var question: String {
        switch self {
        case .quickLook: String(localized: "Reset the Quick Look cache (size unknown)?", table: "Notchcast")
        case .downloadHistory: String(localized: "Clear download history (size unknown)?", table: "Notchcast")
        case .openWithMenu: String(localized: "Rebuild the Open With menu (size unknown)?", table: "Notchcast")
        }
    }
}
