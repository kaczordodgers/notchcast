import SwiftUI

struct NotchcastBackupGroups: View {
    @Environment(AppCore.self) private var core
    @State private var exportSelection = BackupCategory.all
    @State private var exporting = false
    @State private var importing = false
    @State private var status: (message: String, failed: Bool)?

    static func settingsFileSync(core: AppCore) -> Binding<Bool> {
        Binding(
            get: { core.settings.settingsFileEnabled },
            set: { enabled in Task { await BackupActions.setSettingsFileEnabled(enabled, core: core) } })
    }

    var body: some View {
        Section {
            Toggle(isOn: Self.settingsFileSync(core: core)) {
                SettingsRowTitle(.notchcastBackupSettingsFile, "Sync settings file")
                Text(BackupActions.settingsFilePath)
            }
            if core.settings.settingsFileEnabled {
                LabeledContent {
                    Button(String(localized: "Show in Finder"), action: BackupActions.revealSettingsFile)
                } label: {
                    Text("Settings changed here are written to the file, and edits to it apply here.")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastBackupSettingsFile)
        }
        Section {
            LabeledContent {
                if exporting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Export…", action: runExport).disabled(exportSelection.isEmpty)
                }
            } label: {
                SettingsRowTitle(.notchcastBackupExport, "Export Backup")
                Text("The ticked items, as one .tinycast file.")
            }
            BackupCategorySelection(selection: $exportSelection)
            if let status {
                Label(status.message, systemImage: status.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.failed ? .orange : .green)
            }
        } header: {
            SettingsSectionHeader(.notchcastBackupExport)
        }
        Section {
            LabeledContent {
                Button("Choose…") {
                    importing = true
                    Task {
                        defer { importing = false }
                        await BackupActions.runImportCommand(core: core)
                    }
                }
                .disabled(importing)
            } label: {
                SettingsRowTitle(.notchcastBackupImport, "Backup File")
                Text("A .tinycast file exported from Tinycast.")
            }
        } header: {
            SettingsSectionHeader(.notchcastBackupImport)
        }
    }

    private func runExport() {
        guard !exporting else { return }
        exporting = true
        status = nil
        let categories = exportSelection
        Task {
            defer { exporting = false }
            do {
                let result = try await BackupActions.exportBackup(core: core, categories: categories)
                status = (BackupActions.exportText(result), false)
            } catch is CancellationError {
            } catch {
                status = (error.localizedDescription, true)
            }
        }
    }
}
