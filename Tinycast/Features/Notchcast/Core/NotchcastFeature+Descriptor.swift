import Foundation

extension NotchcastFeature {
    /// What the hub states about one feature, declared once in that feature's own folder.
    struct Descriptor: Sendable {
        let title: String
        let subtitle: String
        let group: SettingsGroup
        let needsIsland: Bool
        let defaultEnabled: Bool
        let dependencies: [NotchcastFeature]
        let requiredGrants: [NotchcastGrant]
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
