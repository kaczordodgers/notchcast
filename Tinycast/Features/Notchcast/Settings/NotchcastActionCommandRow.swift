import SwiftUI

struct NotchcastActionCommandRow: View {
    let command: NotchcastCommand
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entry = command.entry
        SettingsRow(title: entry.name, labelOpacity: visibility.isItemVisible(entry) ? 1 : 0.45) {
            AppIconView(app: entry)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: Binding(
                get: { visibility.isItemVisible(entry) },
                set: { visibility.setItemVisible($0, for: entry) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel("Show \(entry.name) in launcher")
            Button(actionTitle, action: command.run)
                .accessibilityLabel(entry.name)
                .settingsEnabled(actionEnabled)
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch command.slug {
        case "settings-showLibrary": "Show"
        case "settings-revealBackup": "Reveal backup folder"
        case "settings-checkUpdates": "Check"
        case "settings-startCleaning": "Start"
        case "settings-cancelUpdate": "Cancel"
        case "settings-installCLI": "Install"
        case "settings-restrictGaming", "settings-restrictMirroring", "settings-restrictMusic", "settings-restrictBooks":
            "Install…"
        case "settings-loadHistory": "Load history"
        case "settings-scanJunk", "settings-scanAI", "settings-scanDisk", "settings-scanProjects": "Scan…"
        default: "Run"
        }
    }

    private var actionEnabled: Bool {
        guard let feature = command.feature else { return true }
        return switch feature {
        case .cleanJunk, .cleanHistory, .cleanAIData, .cleanDisk, .cleanPurge, .cleanOptimize:
            !NotchcastCore.clean.coordinator.busy.contains(feature)
        case .finderTweaks: !NotchcastCore.finderTweaks.store.busy
        case .appleAppsTweaks: !NotchcastCore.appleAppsTweaks.store.busy
        case .appUpdates: !NotchcastCore.appUpdates.checking
        case .macUpdate:
            command.slug == "settings-cancelUpdate" ? NotchcastCore.macUpdate.running : !NotchcastCore.macUpdate.running
        default: true
        }
    }
}
