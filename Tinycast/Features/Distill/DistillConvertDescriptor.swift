import Foundation

extension NotchcastFeature.Descriptor {
    static let distillConvert = Self(
        title: String(localized: "Convert Distill Folder", table: "Notchcast"),
        subtitle: String(localized: "Convert files in your Distill folder to Markdown or text.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
