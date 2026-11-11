import SwiftUI
import AppKit

struct NotchcastCleanActionsSettingRow: View {
    @Environment(CleanCoordinator.self) private var coordinator
    let feature: NotchcastFeature

    var body: some View {
        if feature == .cleanSystem {
            ForEach(CleanSystemPolicy.allowedRoots, id: \.path) { root in
                LabeledContent(root.path) { Text("Report only", tableName: "Notchcast") }
            }
            if !coordinator.helperCurrent {
                Text("Needs the Notchcast helper update", tableName: "Notchcast")
            }
        }
        if feature == .cleanSystem {
            Button(String(localized: "Scan…", table: "Notchcast")) { CleanSettingsActions.scan(feature, coordinator: coordinator) }
                .settingsEnabled(!coordinator.busy.contains(feature))
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
                                Text("Size unavailable", tableName: "Notchcast")
                            }
                            if item.reportOnly { Text("Report only", tableName: "Notchcast") }
                        }
                        .settingsEnabled(!item.reportOnly && !coordinator.busy.contains(feature))
                    }
                }
            }
            .frame(maxHeight: Theme.Size.settingsControlHeight * 8)
            if review.items.isEmpty { Text("No items found.", tableName: "Notchcast") }
            Button(feature == .cleanHistory ? String(localized: "Restore", table: "Notchcast") : String(localized: "Move to trash", table: "Notchcast")) {
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

}

struct NotchcastCleaningModeSettingRow: View {

    var body: some View {
        if NotchcastCore.cleaning.needsGrant {
            Text("Accessibility permission is required to start cleaning mode.", tableName: "Notchcast")
        }
    }
}

struct NotchcastAppUpdatesSettingRow: View {

    var body: some View {
        ForEach(NotchcastCore.appUpdates.results, id: \.app.id) { result in
            LabeledContent(result.app.id) {
                if let newer = result.isNewer {
                    Text(newer ? String(localized: "Update available", table: "Notchcast") : String(localized: "Up to date", table: "Notchcast"))
                    if let latest = result.latest { Text(latest) }
                } else {
                    Text("Unknown", tableName: "Notchcast")
                }
            }
        }

    }
}

struct NotchcastMacUpdateSettingRow: View {

    var body: some View {
        ForEach(MacUpdateStep.allCases, id: \.self) { step in
            if let event = NotchcastCore.macUpdate.progress.first(where: { $0.step == step }) {
                LabeledContent(step.title, value: event.state.title)
            }
        }

    }
}
