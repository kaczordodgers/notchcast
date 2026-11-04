import SwiftUI
import AppKit

struct NotchcastCleanActionsSettingRow: View {
    @Environment(CleanCoordinator.self) private var coordinator
    let feature: NotchcastFeature

    var body: some View {
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
                .settingsEnabled(
                    !coordinator.busy.contains(feature)
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
            .settingsEnabled(
                !(coordinator.selection[feature] ?? []).isEmpty
                    && !coordinator.busy.contains(feature))
        }
    }
    private func selection(_ feature: NotchcastFeature, _ path: URL) -> Binding<Bool> {
        Binding(
            get: { coordinator.selection[feature, default: []].contains(path) },
            set: {
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

struct NotchcastCleaningModeSettingRow: View {

    var body: some View {
        LabeledContent {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if NotchcastCore.cleaning.remaining > 0 {
                    Text(Duration.seconds(NotchcastCore.cleaning.remaining), format: .units())
                }
            }
            Button("Start") { NotchcastCore.cleaning.begin() }
        } label: {
            SettingsRowTitle(.notchcastCleaning, verbatim: NotchcastFeature.cleaningMode.title)
            Text("Media keys still work.")
        }
        if NotchcastCore.cleaning.needsGrant {
            Text("Accessibility permission is required to start cleaning mode.")
        }
    }
}

struct NotchcastAppUpdatesSettingRow: View {

    var body: some View {
        LabeledContent {
            Button("Check") { NotchcastCore.appUpdates.check() }
                .settingsEnabled(!NotchcastCore.appUpdates.checking)
        } label: {
            SettingsRowTitle(.notchcastAppUpdates, verbatim: NotchcastFeature.appUpdates.title)
        }
        ForEach(NotchcastCore.appUpdates.results, id: \.app.id) { result in
            LabeledContent(result.app.id) {
                if let newer = result.isNewer {
                    Text(newer ? String(localized: "Update available") : String(localized: "Up to date"))
                    if let latest = result.latest { Text(latest) }
                } else {
                    Text("Unknown")
                }
            }
        }

    }
}

struct NotchcastMacUpdateSettingRow: View {

    var body: some View {
        LabeledContent {
            Button("Run") { NotchcastCore.macUpdate.run(confirm: NotchcastCore.confirmMacUpdate) }
                .settingsEnabled(!NotchcastCore.macUpdate.running)
        } label: {
            SettingsRowTitle(.notchcastMacUpdate, verbatim: NotchcastFeature.macUpdate.title)
        }
        ForEach(MacUpdateStep.allCases, id: \.self) { step in
            if let event = NotchcastCore.macUpdate.progress.first(where: { $0.step == step }) {
                LabeledContent(step.title, value: event.state.title)
            }
        }
        if NotchcastCore.macUpdate.running {
            Button("Cancel") { NotchcastCore.macUpdate.cancel() }
        }

    }
}
