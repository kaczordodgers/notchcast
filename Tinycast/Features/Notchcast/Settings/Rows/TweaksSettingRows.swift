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
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.")
        case "SystemUIServer":
            String(
                localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.")
        default:
            String(
                localized: "Changes system preferences after confirmation; some changes require signing out.")
        }
    }
}

struct NotchcastAutocorrectSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "autocorrect", title: "Disable autocorrect",
            module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["autocorrect"] ?? [],
            restart: nil)
    }
}

struct NotchcastSmartPunctuationSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "smart-punctuation",
            title: "Disable smart punctuation", module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["smart-punctuation"] ?? [],
            restart: nil)
    }
}

struct NotchcastDoubleSpacePeriodSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "double-space-period",
            title: "Disable double-space period", module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["double-space-period"] ?? [],
            restart: nil)
    }
}

struct NotchcastAutoCapitalizeSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "auto-capitalize",
            title: "Disable auto-capitalization", module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["auto-capitalize"] ?? [],
            restart: nil)
    }
}

struct NotchcastKeyRepeatSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "key-repeat", title: "Enable key repeat",
            module: NotchcastCore.typingTweaks,
            writes: TypingCatalog.writes["key-repeat"] ?? [],
            restart: nil)
    }
}

struct NotchcastFileExtensionsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "file-extensions", title: "Show file extensions",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["file-extensions"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("file-extensions") ? "Finder" : nil)
    }
}

struct NotchcastHiddenFilesSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "hidden-files", title: "Show hidden files",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["hidden-files"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("hidden-files") ? "Finder" : nil)
    }
}

struct NotchcastPathBarSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "path-bar", title: "Show path bar", module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["path-bar"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("path-bar") ? "Finder" : nil)
    }
}

struct NotchcastStatusBarSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "status-bar", title: "Show status bar",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["status-bar"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("status-bar") ? "Finder" : nil)
    }
}

struct NotchcastFoldersFirstSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "folders-first", title: "Keep folders first",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["folders-first"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("folders-first") ? "Finder" : nil)
    }
}

struct NotchcastSearchThisFolderSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "search-this-folder", title: "Search current folder",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["search-this-folder"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("search-this-folder") ? "Finder" : nil)
    }
}

struct NotchcastExtensionWarningSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "extension-warning",
            title: "Disable extension warning", module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["extension-warning"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("extension-warning") ? "Finder" : nil)
    }
}

struct NotchcastPathInTitleSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "path-in-title", title: "Show path in title",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["path-in-title"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("path-in-title") ? "Finder" : nil)
    }
}

struct NotchcastNetworkDsStoreSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "network-ds-store", title: "Avoid network metadata",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["network-ds-store"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("network-ds-store") ? "Finder" : nil)
    }
}

struct NotchcastTrash30DaysSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "trash-30-days", title: "Remove trash after 30 days",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["trash-30-days"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("trash-30-days") ? "Finder" : nil)
    }
}

struct NotchcastSaveLocallySettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "save-locally", title: "Save locally", module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["save-locally"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("save-locally") ? "Finder" : nil)
    }
}

struct NotchcastExpandedSaveSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "expanded-save", title: "Expand save dialogs",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["expanded-save"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("expanded-save") ? "Finder" : nil)
    }
}

struct NotchcastListViewSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "list-view", title: "Use list view", module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["list-view"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("list-view") ? "Finder" : nil)
    }
}

struct NotchcastUsbDsStoreSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "usb-ds-store", title: "Avoid USB metadata",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["usb-ds-store"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("usb-ds-store") ? "Finder" : nil)
    }
}

struct NotchcastDesktopDisksSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "desktop-disks", title: "Hide desktop disks",
            module: NotchcastCore.finderTweaks,
            writes: FinderCatalog.writes["desktop-disks"] ?? [],
            restart: FinderCatalog.requiresFinderRestart.contains("desktop-disks") ? "Finder" : nil)
    }
}

struct NotchcastDockRecentsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "dock-recents", title: "Hide recent apps",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["dock-recents"] ?? [],
            restart: DockCatalog.restartProcess(for: "dock-recents"))
    }
}

struct NotchcastDockDelaySettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "dock-delay", title: "Remove auto-hide delay",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["dock-delay"] ?? [],
            restart: DockCatalog.restartProcess(for: "dock-delay"))
    }
}

struct NotchcastDockBounceSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "dock-bounce", title: "Disable launch animation",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["dock-bounce"] ?? [],
            restart: DockCatalog.restartProcess(for: "dock-bounce"))
    }
}

struct NotchcastMinimizeToAppSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "minimize-to-app", title: "Minimize into app",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["minimize-to-app"] ?? [],
            restart: DockCatalog.restartProcess(for: "minimize-to-app"))
    }
}

struct NotchcastWindowAnimationsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "window-animations",
            title: "Disable window animations", module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["window-animations"] ?? [],
            restart: DockCatalog.restartProcess(for: "window-animations"))
    }
}

struct NotchcastTileMarginsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "tile-margins", title: "Remove tiled window margins",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["tile-margins"] ?? [],
            restart: DockCatalog.restartProcess(for: "tile-margins"))
    }
}

struct NotchcastScreenshotShadowSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "screenshot-shadow", title: "Remove screenshot shadow",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["screenshot-shadow"] ?? [],
            restart: DockCatalog.restartProcess(for: "screenshot-shadow"))
    }
}

struct NotchcastClickToDesktopSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "click-to-desktop", title: "Disable click to desktop",
            module: NotchcastCore.dockTweaks,
            writes: DockCatalog.writes["click-to-desktop"] ?? [],
            restart: DockCatalog.restartProcess(for: "click-to-desktop"))
    }
}

struct NotchcastDesktopWidgetsSettingRow: View {

    var body: some View {
        NotchcastTweaksPreferenceSettingRow(
            identifier: "desktop-widgets", title: "Hide desktop widgets",
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
            Text("Original").tag(0)
            ForEach(values, id: \.self) { value in Text(value.formatted()).tag(value) }
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, title)
        }
        .settingsEnabled(!NotchcastCore.typingTweaks.store.busy)
    }
    private func subtitle(_ restart: String?) -> String {
        switch restart {
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.")
        case "SystemUIServer":
            String(
                localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.")
        default:
            String(
                localized: "Changes system preferences after confirmation; some changes require signing out.")
        }
    }
}

struct NotchcastKeyRepeatSpeedSettingRow: View {

    var body: some View {
        NotchcastKeyRepeatPickerSettingRow(
            identifier: "repeat-rate", title: "Key repeat speed", key: "KeyRepeat", values: [1, 2, 6])
    }
}

struct NotchcastKeyRepeatDelaySettingRow: View {

    var body: some View {
        NotchcastKeyRepeatPickerSettingRow(
            identifier: "repeat-delay", title: "Key repeat delay",
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
                            on: on, title: String(localized: "New Finder windows"),
                            subtitle: subtitle("Finder"), restart: "Finder")
                    }
                })
        ) {
            Text("Original").tag(false)
            Text("Downloads").tag(true)
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, "New Finder windows")
        }
        .settingsEnabled(!NotchcastCore.finderTweaks.store.busy)

    }
    private func subtitle(_ restart: String?) -> String {
        switch restart {
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.")
        case "SystemUIServer":
            String(
                localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.")
        default:
            String(
                localized: "Changes system preferences after confirmation; some changes require signing out.")
        }
    }
}
