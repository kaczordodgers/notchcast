import SwiftUI

struct BackupStatusPathSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(String(localized: "Backup status file path", table: "Notchcast"), text: $preferences.backupStatusPath)
            .textFieldStyle(.roundedBorder)
            .settingsAnchor(.notchcastBackupStatus)
    }
}
