import SwiftUI

struct NotchcastTodoSettings: View {
    var body: some View {
        Section {
            NotchcastFeatureToggle(feature: .tasks, anchor: .notchcastTasks)
            if let module = NotchcastCore.services?.tasks {
                Group {
                    if let store = module.store {
                        Text("\(store.state.tasks.count) tasks · \(module.directory.path)")
                    } else {
                        Text("Task store: \(module.directory.path)")
                    }
                }
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        } header: { SettingsSectionHeader(.notchcastTasks) }
    }
}
