import SwiftUI

struct BackupStatusSettingsSection: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            TextField("Backup status file path", text: $preferences.backupStatusPath)
        } header: {
            SettingsSectionHeader(.notchcastBackupStatus)
        }
        .settingsEnabled(preferences.isOn(.backupStatus))
    }
}

extension SettingsAnchor {
    static let notchcastBackupStatus = Self(tab: .notchcast, title: LocalizedStringResource("Backup Status"))
}
