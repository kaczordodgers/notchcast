import SwiftUI

struct FinderCutPasteSettingRow: View {
    var body: some View {
        LabeledContent {
            Text(verbatim: "⌘X → ⌘V")
        } label: {
            SettingsRowTitle(.notchcastFinder, "Cut and move files")
            Text("A new copy or Escape cancels the cut.")
        }
    }
}

struct FinderRenameSettingRow: View {
    var body: some View {
        LabeledContent {
            Text(verbatim: "⌃⌥⇧⌘R")
        } label: {
            SettingsRowTitle(.notchcastFinder, "Rename selection")
            Text("Uses Finder’s Return key while no text is being edited.")
        }
    }
}

struct ArchiveToolSettingRow: View {
    private let module = NotchcastCore.archives

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                if let tool = module.toolURL {
                    Text("Found")
                    Text(verbatim: tool.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Not found")
                    Text("Install hatchzip and add it to PATH or ~/.local/bin.")
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
        ArchiveJobList(module: NotchcastCore.archives)
    }
}

struct URLCleanerCustomParametersSettingRow: View {
    @Bindable var module: URLCleanerModule
    @State private var draft = URLCleanerRulesDraft()
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Custom parameters", text: $draft.custom)
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
        TextField("Disabled parameters", text: $draft.disabled)
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
        TextField("Per-site parameters", text: $draft.sites)
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
            LabeledContent("Last removed parameters", value: result.removed.joined(separator: ", "))
        }
    }
}
