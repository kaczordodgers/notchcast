import SwiftUI

struct NotchcastModuleSettingsView: View {
    let module: NotchcastSettingsModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Form {
            ForEach(module.groups) { group in
                let anchor = SettingsAnchor(tab: module.tab, title: group.title)
                Section {
                    ForEach(group.items, id: \.self) { item in
                        switch item {
                        case .feature(let feature, let settings):
                            if feature.isWired {
                                NotchcastModuleFeatureRows(feature: feature, settings: settings, anchor: anchor)
                            }
                        case .setting(let setting):
                            NotchcastSettingRow(setting: setting)
                        }
                    }
                } header: {
                    SettingsSectionHeader(anchor)
                }
            }
            if !requiredGrants.isEmpty {
                NotchcastGrantsSection(
                    grants: requiredGrants, anchor: SettingsAnchor(tab: module.tab, title: "Permissions"))
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(module.tab)
        .notchcastEnvironment()
    }

    private var requiredGrants: [NotchcastGrant] {
        let features = module.groups.flatMap(\.items).compactMap(\.feature)
        let needed = Set(features.filter { $0.isWired && preferences.isOn($0) }.flatMap(\.requiredGrants))
        return NotchcastGrant.allCases.filter(needed.contains)
    }
}

private struct NotchcastModuleFeatureRows: View {
    let feature: NotchcastFeature
    let settings: [NotchcastSetting]
    let anchor: SettingsAnchor
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(feature) }, set: { preferences.set(feature, $0) })) {
            SettingsRowTitle(anchor, verbatim: feature.title)
            Text(feature.subtitle)
        }
        .settingsEnabled(preferences.isOn(.island) || !feature.needsIsland)
        .settingsEnabled(feature.dependencies.allSatisfy(preferences.isEnabled))
        if preferences.isEnabled(feature) {
            ForEach(commands, id: \.id) { command in
                FeatureCommandRow(entry: command.entry)
            }
            ForEach(settings, id: \.self) { setting in
                NotchcastSettingRow(setting: setting)
                    .settingsEnabled(preferences.isEnabled(feature))
            }
        }
    }

    private var commands: [NotchcastCommand] {
        NotchcastCommandCatalog.all.filter { $0.feature == feature }
    }
}
