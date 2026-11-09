import Foundation

extension NotchcastFeature {
    /// What the hub states about one feature, declared once in the folder that holds its code.
    struct Descriptor: Sendable {
        let title: String
        let subtitle: String
        let group: SettingsGroup
        let defaultEnabled: Bool
        /// Listing `.island` is what makes a feature island-only; `needsIsland` reads it from here.
        let dependencies: [NotchcastFeature]
        let requiredGrants: [NotchcastGrant]
        let isSystemFeature: Bool
        let isSystemTweak: Bool
    }

    /// One line per described feature; the others still answer from NotchcastFeature's switches.
    static let descriptors: [Self: Descriptor] = [
        .hideCommandM: .hideCommandM,
        .lowDiskWarning: .lowDiskWarning,
        .linkHealth: .linkHealth,
        .eventReminder: .eventReminder,
        .linkQuickFixes: .linkQuickFixes,
    ]

    var descriptor: Descriptor? { Self.descriptors[self] }
}
