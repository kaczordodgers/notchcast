import Foundation

extension NotchcastFeature.Descriptor {
    static let captureTrimmer = Self(
        title: String(localized: "Recording Trimmer", table: "Notchcast"),
        subtitle: String(localized: "Trim recordings and export MP4 or GIF files.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
