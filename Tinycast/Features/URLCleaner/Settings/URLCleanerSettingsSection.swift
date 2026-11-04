import SwiftUI

struct URLCleanerSettingsSection: View {
    @Bindable var module: URLCleanerModule
    @State private var draft = URLCleanerRulesDraft()
    @FocusState private var focused: Field?

    private enum Field: Hashable { case custom, disabled, sites }

    var body: some View {
        Section {
            TextField("Custom parameters", text: $draft.custom).focused($focused, equals: .custom)
            TextField("Disabled parameters", text: $draft.disabled).focused($focused, equals: .disabled)
            TextField("Per-site parameters", text: $draft.sites).focused($focused, equals: .sites)
            if let result = module.lastClean {
                LabeledContent("Last removed parameters", value: result.removed.joined(separator: ", "))
            }
        } header: {
            Text("URL cleaner")
        }
        .onAppear { draft = URLCleanerRulesDraft(module.rules) }
        .onSubmit { save() }
        .onChange(of: focused) { old, _ in if old != nil { save() } }
        .onDisappear { save() }
    }

    private func save() { module.rules = draft.rules }
}
