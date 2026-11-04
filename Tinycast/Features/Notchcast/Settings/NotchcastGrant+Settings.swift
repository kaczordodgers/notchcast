import AppKit
import AVFoundation
import EventKit

extension NotchcastGrant {
    var title: String {
        switch self {
        case .accessibility: SettingsAnchor.permissionsAccessibility.title
        case .screenRecording: String(localized: "Screen Recording")
        case .microphone: SettingsAnchor.permissionsMicrophone.title
        case .calendars: SettingsAnchor.permissionsCalendars.title
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: Permissions.isAccessibilityTrusted()
        case .screenRecording: ScreenshotService.hasScreenRecordingAccess()
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .calendars: EKEventStore.authorizationStatus(for: .event) == .fullAccess
        }
    }

    @MainActor
    func open(_ navigation: SettingsNavigationState) {
        switch self {
        case .accessibility:
            navigation.select(.permissions, revealing: .section(.permissionsAccessibility))
        case .microphone:
            navigation.select(.permissions, revealing: .section(.permissionsMicrophone))
        case .calendars:
            navigation.select(.permissions, revealing: .section(.permissionsCalendars))
        case .screenRecording:
            guard let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
