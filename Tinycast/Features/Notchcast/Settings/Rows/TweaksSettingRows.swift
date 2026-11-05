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

struct NotchcastAutocorrectSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "autocorrect", title: LocalizedStringResource("Disable autocorrect", table: "Notchcast"),
            module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["autocorrect"] ?? [],
            restart: nil)
    }
}

struct NotchcastSmartPunctuationSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "smart-punctuation",
            title: LocalizedStringResource("Disable smart punctuation", table: "Notchcast"), module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["smart-punctuation"] ?? [],
            restart: nil)
    }
}

struct NotchcastDoubleSpacePeriodSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "double-space-period",
            title: LocalizedStringResource("Disable double-space period", table: "Notchcast"), module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["double-space-period"] ?? [],
            restart: nil)
    }
}

struct NotchcastAutoCapitalizeSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "auto-capitalize",
            title: LocalizedStringResource("Disable auto-capitalization", table: "Notchcast"), module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["auto-capitalize"] ?? [],
            restart: nil)
    }
}

struct NotchcastKeyRepeatSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "key-repeat", title: LocalizedStringResource("Enable key repeat", table: "Notchcast"),
            module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["key-repeat"] ?? [],
            restart: nil)
    }
}

struct NotchcastFileExtensionsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "file-extensions", title: LocalizedStringResource("Show file extensions", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["file-extensions"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("file-extensions") ? "Finder" : nil)
    }
}

struct NotchcastHiddenFilesSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "hidden-files", title: LocalizedStringResource("Show hidden files", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["hidden-files"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("hidden-files") ? "Finder" : nil)
    }
}

struct NotchcastPathBarSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "path-bar", title: LocalizedStringResource("Show path bar", table: "Notchcast"), module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["path-bar"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("path-bar") ? "Finder" : nil)
    }
}

struct NotchcastStatusBarSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "status-bar", title: LocalizedStringResource("Show status bar", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["status-bar"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("status-bar") ? "Finder" : nil)
    }
}

struct NotchcastFoldersFirstSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "folders-first", title: LocalizedStringResource("Keep folders first", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["folders-first"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("folders-first") ? "Finder" : nil)
    }
}

struct NotchcastSearchThisFolderSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "search-this-folder", title: LocalizedStringResource("Search current folder", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["search-this-folder"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("search-this-folder") ? "Finder" : nil)
    }
}

struct NotchcastExtensionWarningSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "extension-warning",
            title: LocalizedStringResource("Disable extension warning", table: "Notchcast"), module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["extension-warning"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("extension-warning") ? "Finder" : nil)
    }
}

struct NotchcastPathInTitleSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "path-in-title", title: LocalizedStringResource("Show path in title", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["path-in-title"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("path-in-title") ? "Finder" : nil)
    }
}

struct NotchcastNetworkDsStoreSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "network-ds-store", title: LocalizedStringResource("Avoid network metadata", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["network-ds-store"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("network-ds-store") ? "Finder" : nil)
    }
}

struct NotchcastTrash30DaysSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "trash-30-days", title: LocalizedStringResource("Remove trash after 30 days", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["trash-30-days"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("trash-30-days") ? "Finder" : nil)
    }
}

struct NotchcastSaveLocallySettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "save-locally", title: LocalizedStringResource("Save locally", table: "Notchcast"), module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["save-locally"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("save-locally") ? "Finder" : nil)
    }
}

struct NotchcastExpandedSaveSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "expanded-save", title: LocalizedStringResource("Expand save dialogs", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["expanded-save"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("expanded-save") ? "Finder" : nil)
    }
}

struct NotchcastListViewSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "list-view", title: LocalizedStringResource("Use list view", table: "Notchcast"), module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["list-view"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("list-view") ? "Finder" : nil)
    }
}

struct NotchcastUsbDsStoreSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "usb-ds-store", title: LocalizedStringResource("Avoid USB metadata", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["usb-ds-store"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("usb-ds-store") ? "Finder" : nil)
    }
}

struct NotchcastDesktopDisksSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "desktop-disks", title: LocalizedStringResource("Hide desktop disks", table: "Notchcast"),
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["desktop-disks"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("desktop-disks") ? "Finder" : nil)
    }
}

struct NotchcastDockRecentsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "dock-recents", title: LocalizedStringResource("Hide recent apps", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["dock-recents"] ?? [],
            restart: DockCatalog.restartProcess(for: "dock-recents"))
    }
}

struct NotchcastDockDelaySettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "dock-delay", title: LocalizedStringResource("Remove auto-hide delay", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["dock-delay"] ?? [],
            restart: DockCatalog.restartProcess(for: "dock-delay"))
    }
}

struct NotchcastDockBounceSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "dock-bounce", title: LocalizedStringResource("Disable launch animation", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["dock-bounce"] ?? [],
            restart: DockCatalog.restartProcess(for: "dock-bounce"))
    }
}

struct NotchcastMinimizeToAppSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "minimize-to-app", title: LocalizedStringResource("Minimize into app", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["minimize-to-app"] ?? [],
            restart: DockCatalog.restartProcess(for: "minimize-to-app"))
    }
}

struct NotchcastWindowAnimationsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "window-animations",
            title: LocalizedStringResource("Disable window animations", table: "Notchcast"), module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["window-animations"] ?? [],
            restart: DockCatalog.restartProcess(for: "window-animations"))
    }
}

struct NotchcastTileMarginsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "tile-margins", title: LocalizedStringResource("Remove tiled window margins", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["tile-margins"] ?? [],
            restart: DockCatalog.restartProcess(for: "tile-margins"))
    }
}

struct NotchcastScreenshotShadowSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "screenshot-shadow", title: LocalizedStringResource("Remove screenshot shadow", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["screenshot-shadow"] ?? [],
            restart: DockCatalog.restartProcess(for: "screenshot-shadow"))
    }
}

struct NotchcastClickToDesktopSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "click-to-desktop", title: LocalizedStringResource("Disable click to desktop", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["click-to-desktop"] ?? [],
            restart: DockCatalog.restartProcess(for: "click-to-desktop"))
    }
}

struct NotchcastDesktopWidgetsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "desktop-widgets", title: LocalizedStringResource("Hide desktop widgets", table: "Notchcast"),
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["desktop-widgets"] ?? [],
            restart: DockCatalog.restartProcess(for: "desktop-widgets"))
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
                    if case .integer(let value) = NotchcastCore.typingTweaks.store.plans[identifier]?.entries
                        .first?.write.value
                    {
                        return value
                    }
                    return 0
                },
                set: { value in
                    Task {
                        await NotchcastCore.typingTweaks.set(
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
        .settingsEnabled(!NotchcastCore.typingTweaks.store.busy)
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
            identifier: "repeat-rate", title: LocalizedStringResource("Key repeat speed", table: "Notchcast"), key: "KeyRepeat", values: [1, 2, 6])
    }
}

struct NotchcastKeyRepeatDelaySettingRow: View {

    var body: some View {
        NotchcastKeyRepeatPickerSettingRow(
            identifier: "repeat-delay", title: LocalizedStringResource("Key repeat delay", table: "Notchcast"),
            key: "InitialKeyRepeat", values: [15, 25, 35])
    }
}

struct NotchcastShowLibrarySettingRow: View {

    var body: some View {
        EmptyView()
    }
}

struct NotchcastNewFinderWindowsSettingRow: View {

    var body: some View {
        Picker(
            selection: Binding(
                get: {
                    NotchcastCore.finderTweaks.store.plans["new-window-downloads"] == nil ? false : true
                },
                set: { on in
                    Task {
                        await NotchcastCore.finderTweaks.set(
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
        .settingsEnabled(!NotchcastCore.finderTweaks.store.busy)

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
