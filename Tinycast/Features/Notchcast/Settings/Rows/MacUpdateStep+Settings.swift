import Foundation

extension MacUpdateStep {
    var title: String {
        switch self {
        case .homebrewUpdate: String(localized: "Update Homebrew")
        case .homebrewUpgrade: String(localized: "Upgrade packages")
        case .commandLineTools: String(localized: "Update command-line tools")
        case .appStore: String(localized: "Upgrade App Store apps")
        }
    }
}
