import SwiftUI

struct NotchcastSettingsView: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: binding(.island)) {
                    SettingsFeatureToggleLabel(
                        anchor: .notchcastIsland, title: "Island",
                        subtitle: "Show the island at the top of the screen.")
                }
            } header: { SettingsSectionHeader(.notchcastIsland) }
            .settingsAnchor(.notchcastIsland)

            featureSection(.notchcastOptions, group: .islandOptions)
            featureSection(.notchcastLauncher, group: .launcher)
            featureSection(.notchcastSystem, group: .system)
            BrightnessSettingsSection(controller: NotchcastCore.brightness.controller)
            PasteToolsSettingsSection()
            featureSection(.notchcastFinder, group: .finder)
            FinderSettingsSection()
            QuitProtectionSettingsSection(store: NotchcastCore.quitProtection)
            NotchcastSystemSettingsSection()

            NotchcastExtrasSection()
            AgentPricingSettingsSection()
            BuildStatsSettingsSection()

            CaptureDictationSettingsSection()

            FeatureCommandsSection(owner: .notchcast, anchor: .notchcastShortcuts)

            NotchcastTorrentSettings(module: NotchcastCore.torrents)
            NotchcastTodoSettings()
            NotchcastMusicSettings()
            NotchcastArchiveSettings()
            if !requiredGrants.isEmpty {
                NotchcastGrantsSection(grants: requiredGrants)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast)
        .notchcastEnvironment()
    }

    /// Grants needed by the switches that are on, in a stable order.
    private var requiredGrants: [NotchcastGrant] {
        let needed = Set(NotchcastFeature.allCases.filter(preferences.isOn).flatMap(\.requiredGrants))
        return NotchcastGrant.allCases.filter(needed.contains)
    }

    private func binding(_ feature: NotchcastFeature) -> Binding<Bool> {
        Binding(get: { preferences.isOn(feature) }, set: { preferences.set(feature, $0) })
    }

    private func featureSection(_ anchor: SettingsAnchor, group: NotchcastFeature.SettingsGroup) -> some View {
        Section {
            ForEach(NotchcastFeature.allCases.filter { $0.settingsGroup == group }, id: \.self) { feature in
                Toggle(isOn: binding(feature)) {
                    SettingsRowTitle(anchor, verbatim: feature.title)
                    Text(feature.subtitle)
                }
                .settingsEnabled(preferences.isOn(.island) || !feature.needsIsland)
            }
            if group == .system {
                TextField(text: Binding(
                    get: { preferences.greenMaximizeExcludedApps },
                    set: { preferences.greenMaximizeExcludedApps = $0 })) {
                    SettingsRowTitle(.notchcastSystem, "Excluded app bundle IDs (comma-separated)")
                }
                .settingsEnabled(preferences.isOn(.greenMaximize))
            }
            if group == .islandOptions {
                Picker(selection: Binding(
                    get: { preferences.islandHoverDelay },
                    set: { preferences.islandHoverDelay = $0 })) {
                    ForEach(NotchcastPreferences.HoverDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                } label: {
                    Text("Hover delay")
                }
                .settingsEnabled(preferences.isOn(.island) && preferences.isOn(.islandHoverOpen))
            }
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}

private struct NotchcastGrantsSection: View {
    let grants: [NotchcastGrant]
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Section {
            // Re-read each second, as upstream's Permissions page does, so a grant shows up live.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ForEach(grants, id: \.self) { grant in
                    LabeledContent {
                        HStack(spacing: Theme.Spacing.lg) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: grant.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .accessibilityHidden(true)
                                Text(grant.isGranted ? "Granted" : "Not granted")
                            }
                            .foregroundStyle(grant.isGranted ? .green : .orange)
                            Button("Open…") {
                                grant.open(navigation)
                            }
                        }
                    } label: {
                        Text(grant.title)
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastPermissions)
        }
    }
}

