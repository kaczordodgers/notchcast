import Foundation

extension NotchcastFeature.Descriptor {
    static let hideCommandM = Self(
        title: String(localized: "Hide with ⌘M", table: "Notchcast"),
        subtitle: String(localized: "Hide the front app instead of minimizing its window.", table: "Notchcast"),
        group: .system,
        needsIsland: false,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.accessibility]
    )
}
