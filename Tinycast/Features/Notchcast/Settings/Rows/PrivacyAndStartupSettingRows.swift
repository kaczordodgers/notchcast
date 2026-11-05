import SwiftUI
import AppKit

struct NotchcastAutomaticBackupsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "automatic-backups", title: LocalizedStringResource("Turn off iPhone auto backups", table: "Notchcast"),
            module: NotchcastCore.iPhoneBackupTweaks,
            writes: IPhoneBackupPolicy.writes(automaticBackups: false), restart: nil)
    }
}

struct NotchcastAppleRestrictionSettingRow: View {
    let restriction: AppleAppsPolicy.Restriction
    let title: LocalizedStringResource

    var body: some View {
        EmptyView()
    }
}

struct NotchcastGameCenterSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .gameCenter, title: LocalizedStringResource("Restrict gaming", table: "Notchcast"))
    }
}

struct NotchcastIPhoneMirroringSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .iPhoneMirroring, title: LocalizedStringResource("Restrict iPhone mirroring", table: "Notchcast"))
    }
}

struct NotchcastMusicServiceSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .musicService, title: LocalizedStringResource("Restrict music service", table: "Notchcast"))
    }
}

struct NotchcastBookstoreSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .bookstore, title: LocalizedStringResource("Restrict book store", table: "Notchcast"))
    }
}

struct NotchcastIPhoneBackupFolderSettingRow: View {

    var body: some View {
        Text(
                IPhoneBackupPolicy.backupDirectory(home: FileManager.default.homeDirectoryForCurrentUser).path
        )
    }
}

struct NotchcastStartupItemsSettingRow: View {

    var body: some View {
        Group {
            ForEach(NotchcastCore.systemTools.items, id: \.path) { item in
                if item.disabled == nil || item.loaded == nil {
                    Text(verbatim: item.label)
                } else {
                    Toggle(
                        item.label,
                        isOn: Binding(
                            get: { item.disabled == false },
                            set: { enabled in
                                Task { await NotchcastCore.systemTools.set(item, enabled: enabled) }
                            })
                    )
                    .settingsEnabled(item.kind == .userAgent && !NotchcastCore.systemTools.busy)
                }
            }
        }
        .task { await NotchcastCore.systemTools.refresh() }
    }
}
