import Foundation

extension MacUpdateStep {
    var title: String {
        switch self {
        case .homebrewUpdate: String(localized: "Update Homebrew", table: "Notchcast")
        case .homebrewUpgrade: String(localized: "Upgrade packages", table: "Notchcast")
        case .commandLineTools: String(localized: "Update command-line tools", table: "Notchcast")
        case .appStore: String(localized: "Upgrade App Store apps", table: "Notchcast")
        }
    }
}
