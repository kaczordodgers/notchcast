import Foundation

extension NotchcastFeature.Descriptor {
    static let launcherAnswers = Self(
        title: String(localized: "Currency Answers", table: "Notchcast"),
        subtitle: String(localized: "Currency answers using rates from NBP.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
