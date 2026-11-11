import SwiftUI
import AppKit

struct NotchcastTweaksPreferenceSettingRow: View {
    let identifier: String
    let title: LocalizedStringResource
    let module: TweaksModule
    let writes: [TypingPreferencePlan.Write]
    let restart: String?

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { module.store.plans[identifier] != nil },
                set: { on in
                    Task {
                        await module.set(
                            identifier, writes: writes, on: on,
                            title: String(localized: title), subtitle: subtitle(restart), restart: restart)
                    }
                })
        ) {
            SettingsRowTitle(.notchcastTweaksApps, title)
        }
        .settingsEnabled(!module.store.busy)
    }
    private func subtitle(_ restart: String?) -> String {
        switch restart {
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.", table: "Notchcast")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.", table: "Notchcast")
        case "SystemUIServer":
            String(
                localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.", table: "Notchcast")
        default:
            String(
                localized: "Changes system preferences after confirmation; some changes require signing out.", table: "Notchcast")
        }
    }
}

extension NotchcastTweaksPreferenceSettingRow {
    init(toggle: TweakToggle, module: TweaksModule) {
        self.init(identifier: toggle.id, title: toggle.title, module: module, writes: toggle.writes, restart: toggle.restart)
    }
}

struct NotchcastKeyRepeatPickerSettingRow: View {
    let identifier: String
    let title: LocalizedStringResource
    let key: String
    let values: [Int]

    var body: some View {
        Picker(
            selection: Binding(
                get: {
                    if case .integer(let value) = TweaksModule.typing.store.plans[identifier]?.entries
                        .first?.write.value
                    {
                        return value
                    }
                    return 0
                },
                set: { value in
                    Task {
                        await TweaksModule.typing.set(
                            identifier,
                            writes: [.init(key, .integer(value))], on: value != 0,
                            title: String(localized: title), subtitle: subtitle(nil), restart: nil)
                    }
                })
        ) {
            Text("Original", tableName: "Notchcast").tag(0)
            ForEach(values, id: \.self) { value in Text(value.formatted()).tag(value) }
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, title)
        }
        .settingsEnabled(!TweaksModule.typing.store.busy)
    }
    private func subtitle(_ restart: String?) -> String {
        switch restart {
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.", table: "Notchcast")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.", table: "Notchcast")
        case "SystemUIServer":
            String(
                localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.", table: "Notchcast")
        default:
            String(
                localized: "Changes system preferences after confirmation; some changes require signing out.", table: "Notchcast")
        }
    }
}

struct NotchcastKeyRepeatSpeedSettingRow: View {

    var body: some View {
        NotchcastKeyRepeatPickerSettingRow(
            identifier: "repeat-rate", title: LocalizedStringResource("Key repeat speed", table: "Notchcast"),
            key: "KeyRepeat", values: [1, 2, 6])
    }
}

struct NotchcastKeyRepeatDelaySettingRow: View {

    var body: some View {
        NotchcastKeyRepeatPickerSettingRow(
            identifier: "repeat-delay", title: LocalizedStringResource("Key repeat delay", table: "Notchcast"),
            key: "InitialKeyRepeat", values: [15, 25, 35])
    }
}

struct NotchcastNewFinderWindowsSettingRow: View {

    var body: some View {
        Picker(
            selection: Binding(
                get: {
                    TweaksModule.finder.store.plans["new-window-downloads"] == nil ? false : true
                },
                set: { on in
                    Task {
                        await TweaksModule.finder.set(
                            "new-window-downloads",
                            writes: FinderCatalog.downloads(
                                home: FileManager.default.homeDirectoryForCurrentUser),
                            on: on, title: String(localized: "New Finder windows", table: "Notchcast"),
                            subtitle: subtitle("Finder"), restart: "Finder")
                    }
                })
        ) {
            Text("Original", tableName: "Notchcast").tag(false)
            Text("Downloads", tableName: "Notchcast").tag(true)
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, LocalizedStringResource("New Finder windows", table: "Notchcast"))
        }
        .settingsEnabled(!TweaksModule.finder.store.busy)

    }
    private func subtitle(_ restart: String?) -> String {
        switch restart {
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.", table: "Notchcast")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.", table: "Notchcast")
        case "SystemUIServer":
            String(
                localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.", table: "Notchcast")
        default:
            String(
                localized: "Changes system preferences after confirmation; some changes require signing out.", table: "Notchcast")
        }
    }
}
