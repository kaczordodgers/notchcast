import SwiftUI

/// The rows under the switch: each one's launcher fields, its editor while open and its last output.
struct ScriptCommandsSettingsView: View {
    let context: NotchcastContext
    @State private var editing: String?
    @State private var pendingDeletion: ScriptCommand?
    private static let anchor = NotchcastSettingsSearch.anchor(.launcher)

    var body: some View {
        if let module = context.module(ScriptCommandsModule.self) {
            if module.rows.isEmpty {
                Text("No script commands yet.", tableName: "NotchcastScriptCommands").foregroundStyle(.secondary)
            }
            ForEach(module.rows) { row in
                ScriptCommandRow(
                    row: row, module: module, preferences: context.preferences, isEditing: editing == row.id,
                    onEdit: { editing = editing == row.id ? nil : row.id }, onDelete: { pendingDeletion = row })
                if editing == row.id {
                    ScriptCommandEditor(id: row.id, module: module)
                }
                if let output = module.outputs[row.id] {
                    ScriptCommandOutput(name: row.title, output: output)
                }
            }
            Button {
                editing = module.addRow()
            } label: {
                SettingsRowTitle(Self.anchor, LocalizedStringResource("Add Script Command", table: "NotchcastScriptCommands"))
            }
            .confirmationDialog(
                pendingDeletion.map {
                    String(localized: "Delete “\($0.title)”?", table: "NotchcastScriptCommands")
                } ?? "",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion
            ) { row in
                Button(role: .destructive) {
                    if editing == row.id { editing = nil }
                    module.removeRow(row.id)
                } label: {
                    Text("Delete", tableName: "NotchcastScriptCommands")
                }
            } message: { _ in
                Text("Its alias and shortcut go with it.", tableName: "NotchcastScriptCommands")
            }
        }
    }
}

/// One row as the launcher sees it: name and script, then alias, shortcut and launcher checkbox.
private struct ScriptCommandRow: View {
    let row: ScriptCommand
    let module: ScriptCommandsModule
    let preferences: NotchcastPreferences
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var entryID: String { NotchcastCommand.idPrefix + row.slug }
    private var name: String {
        row.title.isEmpty ? String(localized: "Untitled", table: "NotchcastScriptCommands") : row.title
    }

    // Not SettingsRow: its one-line title truncates beside the row's controls.
    var body: some View {
        let shown = preferences.showsInLauncher(entryID)
        NotchcastCommandRow {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: ScriptCommandsModule.symbol)
                    .fixedSize()
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(name)
                        .fixedSize(horizontal: false, vertical: true)
                    if !row.script.isEmpty {
                        Text(row.script)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.script)
                    }
                }
                .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
            }
        } trailing: {
            if module.running.contains(row.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "\(name) is running", table: "NotchcastScriptCommands"))
            }
            Button(action: onEdit) {
                Image(systemName: isEditing ? "chevron.up" : "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Edit \(name)", table: "NotchcastScriptCommands"))
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Delete \(name)", table: "NotchcastScriptCommands"))
        } controls: {
            Group {
                AliasField(key: entryID, name: name)
                    .settingsEnabled(shown)
                ShortcutRecorder(action: .notchcastCommand(entryID: entryID))
                Toggle(isOn: Binding(get: { shown }, set: { preferences.setShowsInLauncher(entryID, $0) })) {
                    NotchcastLauncherCheckboxLabel(title: Text("Show in launcher", tableName: "NotchcastScriptCommands"))
                }
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(String(localized: "Show \(name) in the launcher", table: "NotchcastScriptCommands"))
            }
            .settingsEnabled(row.isRunnable)
        }
    }
}
