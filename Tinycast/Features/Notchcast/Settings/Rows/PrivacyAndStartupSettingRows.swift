import SwiftUI
import AppKit

struct NotchcastAutomaticBackupsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "automatic-backups", title: "Turn off iPhone auto backups",
            module: NotchcastCore.iPhoneBackupTweaks,
            writes: IPhoneBackupPolicy.writes(automaticBackups: false), restart: nil)
    }
}

struct NotchcastAppleRestrictionSettingRow: View {
    let restriction: AppleAppsPolicy.Restriction
    let title: LocalizedStringResource

    var body: some View {
        Button {
            Task { await NotchcastCore.appleAppsTweaks.handOffProfile(restriction) }
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, title)
            Text("macOS requires your approval to install this restriction; remove it in System Settings.")
        }
        .settingsEnabled(!NotchcastCore.appleAppsTweaks.store.busy)
    }
}

struct NotchcastGameCenterSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .gameCenter, title: "Restrict gaming")
    }
}

struct NotchcastIPhoneMirroringSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .iPhoneMirroring, title: "Restrict iPhone mirroring")
    }
}

struct NotchcastMusicServiceSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .musicService, title: "Restrict music service")
    }
}

struct NotchcastBookstoreSettingRow: View {

    var body: some View {
        NotchcastAppleRestrictionSettingRow(restriction: .bookstore, title: "Restrict book store")
    }
}

struct NotchcastIPhoneBackupFolderSettingRow: View {

    var body: some View {
        LabeledContent {
            Button("Reveal backup folder") {
                NSWorkspace.shared.selectFile(
                    nil,
                    inFileViewerRootedAtPath:
                        IPhoneBackupPolicy.backupDirectory(
                            home: FileManager.default.homeDirectoryForCurrentUser
                        ).path)
            }
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, "iPhone backup folder")
            Text(
                IPhoneBackupPolicy.backupDirectory(home: FileManager.default.homeDirectoryForCurrentUser).path
            )
        }
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
