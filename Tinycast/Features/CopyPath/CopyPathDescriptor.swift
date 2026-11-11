import Foundation

extension NotchcastFeature.Descriptor {
    static let copyPath = Self(
        title: String(localized: "Copy Path"),
        subtitle: String(localized: "Copy the frontmost document path or browser link.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
