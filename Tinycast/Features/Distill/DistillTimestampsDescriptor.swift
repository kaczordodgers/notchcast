import Foundation

extension NotchcastFeature.Descriptor {
    static let distillTimestamps = Self(
        title: String(localized: "Distill Timestamps", table: "Notchcast"),
        subtitle: String(localized: "Include approximate chunk timestamps in Distill transcripts.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
