import Foundation

extension NotchcastFeature.Descriptor {
    static let lowDiskWarning = Self(
        title: String(localized: "Low Disk Warning", table: "Notchcast"),
        subtitle: String(localized: "Warns below \(10)% or \(30) GB free.", table: "Notchcast"),
        group: .system,
        needsIsland: true,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: []
    )
}
