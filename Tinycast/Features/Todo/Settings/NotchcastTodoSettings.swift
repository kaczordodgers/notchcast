import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchcastTodoSettings: View {
    @State private var selectedFile: URL?
    @State private var result: String?
    var body: some View {
        Section {
            NotchcastFeatureToggle(feature: .tasks, anchor: .notchcastTasks)
            if let module = NotchcastCore.services?.tasks {
                if let store = module.store {
                    Text("Tasks: \(store.state.tasks.count)").foregroundStyle(.secondary)
                }
                Button("Import Todoist JSON export…", action: selectFile)
                    .help("Accepts a JSON object with Todoist tasks, projects, sections and labels arrays.")
                    .disabled(module.store == nil || selectedFile != nil)
                    .settingsAnchor(.notchcastTasks)
                if let result { Text(result).foregroundStyle(.secondary) }
            }
        } header: { SettingsSectionHeader(.notchcastTasks) }
        .task(id: selectedFile) {
            guard let url = selectedFile, let module = NotchcastCore.services?.tasks,
                  let store = module.store else { return }
            defer { selectedFile = nil }
            do {
                let data = try await TodoistImportClient.export(from: FixtureExportSource(url: url))
                try Task.checkCancellation()
                guard module.store === store else { return }
                let count = try TodoSettingsImport.apply(data, to: store, now: Date(),
                    calendar: .current, timeZone: .current)
                result = String(localized: "Imported tasks: \(count)")
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, module.store === store else { return }
                result = String(localized: "The file is not a Todoist JSON export.")
            }
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            result = nil
            selectedFile = url
        }
    }
}
