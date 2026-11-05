import SwiftUI

struct NotchcastModuleSettingsView: View {
    let module: NotchcastSettingsModule
    @Environment(AppCore.self) private var core
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Form {
            if module == .backups { NotchcastBackupGroups() }
            ForEach(module.visibleGroups) { group in
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
        .environment(core.appearanceCoordinator)
        .environment(NotchcastCore.clean.coordinator)
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
        Toggle(isOn: Binding(get: { preferences.isOn(feature) }, set: { feature.setFromSettings($0) })) {
            SettingsRowTitle(anchor, verbatim: feature.title)
            if feature.helperLocked {
                Text("Needs the Notchcast helper update", tableName: "Notchcast")
            } else {
                // One Text, so a second caption line keeps the description's size.
                Text([feature.subtitle, detail].compactMap(\.self).joined(separator: "\n"))
            }
            if feature == .cleaningMode {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if NotchcastCore.cleaning.remaining > 0 {
                        Text("\(Duration.seconds(NotchcastCore.cleaning.remaining).formatted(.units())) left")
                    }
                }
            }
        }
        .settingsEnabled(preferences.isOn(.island) || !feature.needsIsland)
        .settingsEnabled(feature.dependencies.allSatisfy(preferences.isEnabled))
        .settingsEnabled(feature.settingsAvailable)
        if NotchcastSettingsModule.module(of: feature) == .battery && ![.accessoryBatteries, .accessoryNotices].contains(feature) {
            NotchcastBatteryStatusSettingRow(feature: feature)
        }
        if feature == .microphoneMute, servicesReady {
            MicrophoneHotKeyFailureSettingRow()
        }
        if preferences.isEnabled(feature) && feature.settingsAvailable {
            ForEach(commands, id: \.id) { command in
                if command.slug.hasPrefix("settings-") {
                    NotchcastActionCommandRow(command: command)
                } else {
                    FeatureCommandRow(entry: command.entry)
                }
            }
            ForEach(servicesReady ? settings : [], id: \.self) { setting in
                NotchcastSettingRow(setting: setting)
                    .settingsEnabled(preferences.isEnabled(feature))
            }
        }
    }

    private var detail: String? {
        switch feature {
        case .dockTweaks: String(localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.", table: "Notchcast")
        case .cleaningMode: String(localized: "Media keys still work.", table: "Notchcast")
        case .cleanAIData: String(localized: "Codex and OpenCode are report-only.", table: "Notchcast")
        default: nil
        }
    }

    /// Spotify and microphone rows read services that `NotchcastCore.start` creates; the offscreen gallery never starts them.
    private var servicesReady: Bool {
        NotchcastCore.services != nil || ![.spotifyConnect, .microphoneMute, .inUseMarks].contains(feature)
    }

    private var commands: [NotchcastCommand] {
        NotchcastCommandCatalog.all.filter { $0.feature == feature }
    }
}
