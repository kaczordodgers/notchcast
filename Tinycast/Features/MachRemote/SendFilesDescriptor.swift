import Foundation

extension NotchcastFeature.Descriptor {
    static let sendFiles = Self(
        title: String(localized: "Send to Remote Mac", table: "Notchcast"),
        subtitle: String(localized: "Send selected files to the remote Mac.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
