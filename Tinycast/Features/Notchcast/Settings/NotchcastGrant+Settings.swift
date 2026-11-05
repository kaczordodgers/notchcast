import AppKit
import AVFoundation
import CoreBluetooth
import EventKit

extension NotchcastGrant {
    var title: String {
        switch self {
        case .accessibility: SettingsAnchor.permissionsAccessibility.title
        case .screenRecording: String(localized: "Screen Recording", table: "Notchcast")
        case .microphone: SettingsAnchor.permissionsMicrophone.title
        case .calendars: SettingsAnchor.permissionsCalendars.title
        case .bluetooth: String(localized: "Bluetooth", table: "Notchcast")
        }
    }

    @concurrent
    func readIsGranted() async -> Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .calendars: EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .bluetooth: CBManager.authorization == .allowedAlways
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
        case .bluetooth:
            guard let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
