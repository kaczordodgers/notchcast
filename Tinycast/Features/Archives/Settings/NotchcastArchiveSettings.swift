import SwiftUI

struct NotchcastArchiveSettings: View {
    private let preferences = NotchcastPreferences.shared
    private let module = NotchcastCore.archives

    var body: some View {
        Section {
            toggle(.archives)
            toggle(.archivesInPlace)
                .settingsEnabled(preferences.isOn(.archives))
            toggle(.archivesDefaultApp)
                .settingsEnabled(preferences.isOn(.archives))
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
            if let failure = module.defaultApplicationFailure {
                Text(failure)
                    .foregroundStyle(.secondary)
            }
            ArchiveJobList(module: module)
        } header: {
            SettingsSectionHeader(.notchcastArchives)
        }
        .task { await module.refreshTool() }
    }

    private func toggle(_ feature: NotchcastFeature) -> some View {
        Toggle(isOn: Binding(get: { preferences.isOn(feature) }, set: { preferences.set(feature, $0) })) {
            SettingsRowTitle(.notchcastArchives, verbatim: feature.title)
            Text(feature.subtitle)
        }
        .accessibilityLabel(feature.title)
        .accessibilityHint(feature.subtitle)
    }
}
