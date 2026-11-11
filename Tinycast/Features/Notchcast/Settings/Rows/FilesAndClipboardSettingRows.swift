import SwiftUI

struct FinderCutPasteSettingRow: View {
    var body: some View {
        LabeledContent {
            Text(verbatim: "⌘X → ⌘V")
        } label: {
            SettingsRowTitle(.notchcastFinder, LocalizedStringResource("Cut and move files", table: "Notchcast"))
            Text("A new copy or Escape cancels the cut.", tableName: "Notchcast")
        }
    }
}

struct FinderRenameSettingRow: View {
    var body: some View {
        LabeledContent {
            Text(verbatim: "⌃⌥⇧⌘R")
        } label: {
            SettingsRowTitle(.notchcastFinder, LocalizedStringResource("Rename selection", table: "Notchcast"))
            Text("Uses Finder’s Return key while no text is being edited.", tableName: "Notchcast")
        }
    }
}

struct ArchiveToolSettingRow: View {
    private let module = ArchiveModule.shared

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                if let tool = module.toolURL {
                    Text("Found", tableName: "Notchcast")
                    Text(verbatim: tool.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Not found", tableName: "Notchcast")
                    Text("Install hatchzip and add it to PATH or ~/.local/bin.", tableName: "Notchcast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(verbatim: "hatchzip")
        }
        .task { await module.refreshTool() }
        if let failure = module.defaultApplicationFailure {
            Text(failure)
                .foregroundStyle(.secondary)
        }
    }
}

struct ArchiveJobsSettingRow: View {
    var body: some View {
        ArchiveJobList(module: .shared)
    }
}

struct URLCleanerCustomParametersSettingRow: View {
    @Bindable var module: URLCleanerModule
    @State private var draft = URLCleanerRulesDraft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(localized: "Custom parameters", table: "Notchcast"), text: $draft.custom)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = URLCleanerRulesDraft(module.rules) }
            .onSubmit { save() }
            .onChange(of: focused) { old, _ in if old { save() } }
            .onDisappear { save() }
    }

    private func save() {
        var updated = URLCleanerRulesDraft(module.rules)
        updated.custom = draft.custom
        module.rules = updated.rules
    }
}

struct URLCleanerDisabledParametersSettingRow: View {
    @Bindable var module: URLCleanerModule
    @State private var draft = URLCleanerRulesDraft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(localized: "Disabled parameters", table: "Notchcast"), text: $draft.disabled)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = URLCleanerRulesDraft(module.rules) }
            .onSubmit { save() }
            .onChange(of: focused) { old, _ in if old { save() } }
            .onDisappear { save() }
    }

    private func save() {
        var updated = URLCleanerRulesDraft(module.rules)
        updated.disabled = draft.disabled
        module.rules = updated.rules
    }
}

struct URLCleanerSiteParametersSettingRow: View {
    @Bindable var module: URLCleanerModule
    @State private var draft = URLCleanerRulesDraft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(localized: "Per-site parameters", table: "Notchcast"), text: $draft.sites)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = URLCleanerRulesDraft(module.rules) }
            .onSubmit { save() }
            .onChange(of: focused) { old, _ in if old { save() } }
            .onDisappear { save() }
    }

    private func save() {
        var updated = URLCleanerRulesDraft(module.rules)
        updated.sites = draft.sites
        module.rules = updated.rules
    }
}

struct URLCleanerLastRemovedSettingRow: View {
    let module: URLCleanerModule

    var body: some View {
        if let result = module.lastClean {
            LabeledContent(String(localized: "Last removed parameters", table: "Notchcast"), value: result.removed.joined(separator: ", "))
        }
    }
}
