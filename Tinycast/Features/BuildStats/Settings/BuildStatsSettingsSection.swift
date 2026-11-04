import SwiftUI

struct BuildStatsSettingsSection: View {
    @Bindable private var preferences = NotchcastPreferences.shared
    @State private var state: BuildStatsLoader.State = .unconfigured

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.isOn(.buildStats) },
                set: { preferences.set(.buildStats, $0) })) {
                SettingsRowTitle(.notchcastBuildStats, verbatim: NotchcastFeature.buildStats.title)
                Text(NotchcastFeature.buildStats.subtitle)
            }
            TextField("Snapshot path", text: $preferences.buildStatsPath)
                .settingsEnabled(preferences.isOn(.buildStats))
            Text(verbatim: status)
                .lineLimit(1)
        } header: {
            SettingsSectionHeader(.notchcastBuildStats)
        }
        .task(id: LoadRequest(path: preferences.buildStatsPath, enabled: preferences.isOn(.buildStats))) {
            guard preferences.isOn(.buildStats) else { return }
            let path = preferences.buildStatsPath
            let result = await BuildStatsLoader.load(path: path)
            guard !Task.isCancelled, preferences.buildStatsPath == path,
                  preferences.isOn(.buildStats) else { return }
            state = result
        }
    }

    private struct LoadRequest: Equatable {
        let path: String
        let enabled: Bool
    }

    private var status: String {
        switch state {
        case .unconfigured: String(localized: "No snapshot loaded.")
        case let .loaded(model):
            String(localized: "Loaded: \(model.entryCount) entries, updated \(model.modificationDate.formatted(.relative(presentation: .named)))")
        case .failed(.missing): String(localized: "Snapshot file is missing.")
        case .failed(.unreadable): String(localized: "Snapshot file cannot be read.")
        case .failed(.tooLarge): String(localized: "Snapshot file is too large.")
        case .failed(.invalid), .failed(.overflow): String(localized: "Snapshot file is invalid.")
        }
    }
}
