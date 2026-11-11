import Foundation

extension NotchcastFeature.Descriptor {
    static let downloads = Self(
        title: String(localized: "Downloads", table: "Notchcast"),
        subtitle: String(localized: "Download video, audio, transcripts and webpages from clipboard links.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
