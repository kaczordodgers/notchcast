import SwiftUI

struct BackupStatusPathSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField("Backup status file path", text: $preferences.backupStatusPath)
            .onChange(of: preferences.backupStatusPath) { NotchcastCore.backupStatus.pathChanged() }
            .settingsAnchor(.notchcastBackupStatus)
    }
}
