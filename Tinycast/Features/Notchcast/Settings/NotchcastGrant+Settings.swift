import AppKit

extension NotchcastGrant {
    var title: String {
        switch self {
        case .accessibility: SettingsAnchor.permissionsAccessibility.title
        case .screenRecording: String(localized: "Screen Recording")
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: Permissions.isAccessibilityTrusted()
        case .screenRecording: ScreenshotService.hasScreenRecordingAccess()
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
        }
    }
}
