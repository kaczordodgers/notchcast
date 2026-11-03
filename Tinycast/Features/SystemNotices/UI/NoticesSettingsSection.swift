import SwiftUI

struct NoticesSettingsSection: View {
    @Bindable var preferences: SystemNoticesPreferences
    private let switches = NotchcastPreferences.shared

    var body: some View {
        Section {
            NotchcastFeatureToggle(feature: .systemNotices, anchor: .notchcastNotices,
                                  title: "System notices", subtitle: "Wi-Fi, Tailscale and low battery notices in the island.")
            if switches.isOn(.systemNotices) {
                Toggle(isOn: $preferences.wifi) {
                    SettingsRowTitle(.notchcastNotices, "Wi-Fi")
                    Text("When Wi-Fi connects or drops.")
                }
                Toggle(isOn: $preferences.tailscale) {
                    SettingsRowTitle(.notchcastNotices, "Tailscale")
                    Text(tailscaleInstalled ? "When Tailscale connects, drops or needs you." : "Tailscale isn’t installed.")
                }
                .settingsEnabled(tailscaleInstalled)
                Toggle(isOn: $preferences.battery) {
                    SettingsRowTitle(.notchcastNotices, "Low battery")
                    Text("At \(20)% and \(10)% while on battery.")
                }
            }
            NotchcastFeatureToggle(feature: .lowDiskWarning, anchor: .notchcastNotices,
                                  title: "Low disk space", subtitle: "Warns below \(10)% or \(30) GB free.")
        } header: {
            SettingsSectionHeader(.notchcastNotices)
        }
        .settingsEnabled(switches.isOn(.island))
    }

    private var tailscaleInstalled: Bool {
        ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale",
         "/Applications/Tailscale.app/Contents/MacOS/Tailscale"].contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}
