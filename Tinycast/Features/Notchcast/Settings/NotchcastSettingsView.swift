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
            }
            .settingsAnchor(.notchcastIsland)

            Section {
                ForEach(NotchcastFeature.allCases.filter { $0 != .island && !$0.isSystemFeature }, id: \.self) { feature in
                    Toggle(isOn: binding(feature)) {
                        SettingsRowTitle(.notchcastOptions, verbatim: feature.title)
                        Text(feature.subtitle)
                    }
                    .settingsEnabled(preferences.isOn(.island) || !feature.needsIsland)
                }
            } header: {
                SettingsSectionHeader(.notchcastOptions)
            }

            BrightnessSettingsSection(controller: NotchcastCore.brightness.controller)
            QuitProtectionSettingsSection(store: NotchcastCore.quitProtection)
            TimerSettingsSection(store: NotchcastCore.timers.store)
            DaySettingsSection(weather: NotchcastCore.weather.store, markets: NotchcastCore.markets.store)

            NotchcastSystemSettingsSection()

            Section {
                Picker(selection: Binding(
                    get: { preferences.islandHoverDelay },
                    set: { preferences.islandHoverDelay = $0 })) {
                    ForEach(NotchcastPreferences.HoverDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                } label: {
                    Text("Hover delay")
                }
                .settingsEnabled(preferences.isOn(.islandHoverOpen))
            }
            .settingsEnabled(preferences.isOn(.island))

            FeatureCommandsSection(owner: .notchcast, anchor: .notchcastShortcuts)
                .settingsEnabled(preferences.isOn(.island))

            if !requiredGrants.isEmpty {
                NotchcastGrantsSection(grants: requiredGrants)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast)
    }

    /// Grants needed by the switches that are on, in a stable order.
    private var requiredGrants: [NotchcastGrant] {
        let needed = Set(NotchcastFeature.allCases.filter(preferences.isOn).flatMap(\.requiredGrants))
        return NotchcastGrant.allCases.filter(needed.contains)
    }

    private func binding(_ feature: NotchcastFeature) -> Binding<Bool> {
        Binding(get: { preferences.isOn(feature) }, set: { preferences.set(feature, $0) })
    }
}

/// Read-only: grants are given on upstream's Permissions page, so this never prompts.
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
                                navigation.select(.permissions, revealing: .section(grant.anchor))
                            }
                        }
                    } label: {
                        Text(grant.anchor.title)
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastPermissions)
        }
    }
}

private extension NotchcastGrant {
    var anchor: SettingsAnchor {
        switch self {
        case .accessibility: .permissionsAccessibility
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: Permissions.isAccessibilityTrusted()
        }
    }
}
