import Foundation

extension NotchcastFeature.Descriptor {
    static let remoteScreen = Self(
        title: String(localized: "Remote Screen", table: "Notchcast"),
        subtitle: String(localized: "Request screen sharing with the paired Mac.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.machLink],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
