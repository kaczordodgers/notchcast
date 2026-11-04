import AppKit
import CoreBluetooth

extension NotchcastGrant {
    var title: String {
        switch self {
        case .accessibility: SettingsAnchor.permissionsAccessibility.title
        case .screenRecording: String(localized: "Screen Recording")
        case .bluetooth: String(localized: "Bluetooth")
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: Permissions.isAccessibilityTrusted()
        case .screenRecording: ScreenshotService.hasScreenRecordingAccess()
        case .bluetooth: CBManager.authorization == .allowedAlways
        }
    }

    @MainActor
    func open(_ navigation: SettingsNavigationState) {
        switch self {
        case .accessibility:
            navigation.select(.permissions, revealing: .section(.permissionsAccessibility))
        case .screenRecording:
            guard let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
            NSWorkspace.shared.open(url)
        case .bluetooth:
            guard let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
