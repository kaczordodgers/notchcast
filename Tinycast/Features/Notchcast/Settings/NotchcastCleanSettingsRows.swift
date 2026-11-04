import SwiftUI

struct NotchcastCleanSettingsRows: View {
    @Environment(CleanCoordinator.self) private var coordinator
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        ForEach(CleanCoordinator.features.filter(\.isWired), id: \.self) { feature in
            Toggle(isOn: binding(feature)) {
                SettingsRowTitle(.notchcastClean, verbatim: feature.title)
                Text(feature.subtitle)
            }
            if preferences.isOn(feature) {
                if feature == .cleanAIData {
                    Text("Codex and OpenCode are report-only.")
                }
                if feature == .cleanSystem {
                    ForEach(CleanSystemPolicy.allowedRoots, id: \.path) { root in
                        LabeledContent(root.path) { Text("Report only") }
                    }
                    if !coordinator.rootAvailable {
                        Text("Needs the Notchcast helper update")
                    }
                }
                if feature == .cleanOptimize {
                    ForEach(CleanOptimizeTask.allCases, id: \.self) { task in
                        Button(task.title) { coordinator.optimize(task) }
                            .settingsEnabled(!coordinator.busy.contains(feature))
                    }
                } else {
                    Button(feature == .cleanHistory ? "Load history" : "Scan…") { scan(feature) }
                        .settingsEnabled(!coordinator.busy.contains(feature)
                            && (feature != .cleanSystem || coordinator.rootAvailable))
                }
                if coordinator.busy.contains(feature) { ProgressView() }
                if let review = coordinator.reviews[feature] {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(review.items) { item in
                                Toggle(isOn: selection(feature, item.id)) {
                                    Text(item.id.path).textSelection(.enabled)
                                    if let detail = item.detail { Text(detail) }
                                    if let size = item.size {
                                        Text(size.formatted(.byteCount(style: .file)))
                                    } else {
                                        Text("Size unavailable")
                                    }
                                    if item.reportOnly { Text("Report only") }
                                }
                                .settingsEnabled(!item.reportOnly && !coordinator.busy.contains(feature))
                            }
                        }
                    }
                    .frame(maxHeight: Theme.Size.settingsControlHeight * 8)
                    if review.items.isEmpty { Text("No items found.") }
                    Button(feature == .cleanHistory ? "Restore" : "Move to trash") {
                        coordinator.apply(feature)
                    }
                    .settingsEnabled(!(coordinator.selection[feature] ?? []).isEmpty
                        && !coordinator.busy.contains(feature))
                }
            }
        }
    }

    private func binding(_ feature: NotchcastFeature) -> Binding<Bool> {
        Binding(get: { preferences.isOn(feature) }, set: { NotchcastCore.clean.set(feature, $0) })
    }

    private func selection(_ feature: NotchcastFeature, _ path: URL) -> Binding<Bool> {
        Binding(get: { coordinator.selection[feature, default: []].contains(path) }, set: {
            if $0 {
                coordinator.selection[feature, default: []].insert(path)
            } else {
                coordinator.selection[feature, default: []].remove(path)
            }
        })
    }

    private func scan(_ feature: NotchcastFeature) {
        guard feature == .cleanDisk || feature == .cleanPurge else {
            coordinator.scan(feature)
            return
        }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = feature == .cleanPurge
        picker.canCreateDirectories = false
        picker.begin { response in
            guard response == .OK else { return }
            coordinator.scan(feature, roots: picker.urls)
        }
    }
}
