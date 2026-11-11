import Foundation

extension NotchcastFeature.Descriptor {
    static let launcherNumberKeys = Self(
        title: String(localized: "Launcher Number Keys", table: "Notchcast"),
        subtitle: String(localized: "Open the first nine search results with Command-1 through Command-9.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
