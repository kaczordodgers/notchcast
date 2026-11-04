import SwiftUI
import AppKit

struct NotchcastTweaksAppsSettingsRows: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Group {
            typingRows
            finderRows
            dockRows
            appleAppsRows
            backupRows
        }
    }

    private var typingRows: some View {
        Group {
            featureSwitch(.typingTweaks)
            repeatPicker("repeat-rate", title: "Key repeat speed", key: "KeyRepeat", values: [1, 2, 6])
            repeatPicker("repeat-delay", title: "Key repeat delay", key: "InitialKeyRepeat", values: [15, 25, 35])
            preference("autocorrect", title: "Disable autocorrect", module: NotchcastCore.typingTweaks,
                       feature: .typingTweaks, writes: TypingCatalog.writes["autocorrect"] ?? [],
                       restart: nil)
            preference("smart-punctuation", title: "Disable smart punctuation", module: NotchcastCore.typingTweaks,
                       feature: .typingTweaks, writes: TypingCatalog.writes["smart-punctuation"] ?? [],
                       restart: nil)
            preference("double-space-period", title: "Disable double-space period", module: NotchcastCore.typingTweaks,
                       feature: .typingTweaks, writes: TypingCatalog.writes["double-space-period"] ?? [],
                       restart: nil)
            preference("auto-capitalize", title: "Disable auto-capitalization", module: NotchcastCore.typingTweaks,
                       feature: .typingTweaks, writes: TypingCatalog.writes["auto-capitalize"] ?? [],
                       restart: nil)
            preference("key-repeat", title: "Enable key repeat", module: NotchcastCore.typingTweaks,
                       feature: .typingTweaks, writes: TypingCatalog.writes["key-repeat"] ?? [],
                       restart: nil)
        }
    }

    private var finderRows: some View {
        Group {
            featureSwitch(.finderTweaks)
            Button {
                Task { await NotchcastCore.finderTweaks.showLibrary() }
            } label: {
                SettingsRowTitle(.notchcastTweaksApps, "Show library")
                Text("Make your Library folder visible in Finder.")
            }
            .settingsEnabled(preferences.isOn(.finderTweaks) && !NotchcastCore.finderTweaks.store.busy)
            Picker(selection: Binding(get: {
                NotchcastCore.finderTweaks.store.plans["new-window-downloads"] == nil ? false : true
            }, set: { on in
                Task { await NotchcastCore.finderTweaks.set("new-window-downloads",
                    writes: FinderCatalog.downloads(home: FileManager.default.homeDirectoryForCurrentUser),
                    on: on, title: String(localized: "New Finder windows"),
                    subtitle: subtitle("Finder"), restart: "Finder") }
            })) {
                Text("Original").tag(false)
                Text("Downloads").tag(true)
            } label: {
                SettingsRowTitle(.notchcastTweaksApps, "New Finder windows")
                Text(subtitle("Finder"))
            }
            .settingsEnabled(preferences.isOn(.finderTweaks) && !NotchcastCore.finderTweaks.store.busy)
            preference("file-extensions", title: "Show file extensions", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["file-extensions"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("file-extensions") ? "Finder" : nil)
            preference("hidden-files", title: "Show hidden files", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["hidden-files"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("hidden-files") ? "Finder" : nil)
            preference("path-bar", title: "Show path bar", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["path-bar"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("path-bar") ? "Finder" : nil)
            preference("status-bar", title: "Show status bar", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["status-bar"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("status-bar") ? "Finder" : nil)
            preference("folders-first", title: "Keep folders first", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["folders-first"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("folders-first") ? "Finder" : nil)
            preference("search-this-folder", title: "Search current folder", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["search-this-folder"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("search-this-folder") ? "Finder" : nil)
            preference("extension-warning", title: "Disable extension warning", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["extension-warning"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("extension-warning") ? "Finder" : nil)
            preference("path-in-title", title: "Show path in title", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["path-in-title"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("path-in-title") ? "Finder" : nil)
            preference("network-ds-store", title: "Avoid network metadata", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["network-ds-store"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("network-ds-store") ? "Finder" : nil)
            preference("trash-30-days", title: "Remove trash after 30 days", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["trash-30-days"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("trash-30-days") ? "Finder" : nil)
            preference("save-locally", title: "Save locally", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["save-locally"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("save-locally") ? "Finder" : nil)
            preference("expanded-save", title: "Expand save dialogs", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["expanded-save"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("expanded-save") ? "Finder" : nil)
            preference("list-view", title: "Use list view", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["list-view"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("list-view") ? "Finder" : nil)
            preference("usb-ds-store", title: "Avoid USB metadata", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["usb-ds-store"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("usb-ds-store") ? "Finder" : nil)
            preference("desktop-disks", title: "Hide desktop disks", module: NotchcastCore.finderTweaks,
                       feature: .finderTweaks, writes: FinderCatalog.writes["desktop-disks"] ?? [],
                       restart: FinderCatalog.requiresFinderRestart.contains("desktop-disks") ? "Finder" : nil)
        }
    }

    private var dockRows: some View {
        Group {
            featureSwitch(.dockTweaks)
            preference("dock-recents", title: "Hide recent apps", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["dock-recents"] ?? [],
                       restart: DockCatalog.restartProcess(for: "dock-recents"))
            preference("dock-delay", title: "Remove auto-hide delay", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["dock-delay"] ?? [],
                       restart: DockCatalog.restartProcess(for: "dock-delay"))
            preference("dock-bounce", title: "Disable launch animation", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["dock-bounce"] ?? [],
                       restart: DockCatalog.restartProcess(for: "dock-bounce"))
            preference("minimize-to-app", title: "Minimize into app", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["minimize-to-app"] ?? [],
                       restart: DockCatalog.restartProcess(for: "minimize-to-app"))
            preference("window-animations", title: "Disable window animations", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["window-animations"] ?? [],
                       restart: DockCatalog.restartProcess(for: "window-animations"))
            preference("tile-margins", title: "Remove tiled window margins", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["tile-margins"] ?? [],
                       restart: DockCatalog.restartProcess(for: "tile-margins"))
            preference("screenshot-shadow", title: "Remove screenshot shadow", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["screenshot-shadow"] ?? [],
                       restart: DockCatalog.restartProcess(for: "screenshot-shadow"))
            preference("click-to-desktop", title: "Disable click to desktop", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["click-to-desktop"] ?? [],
                       restart: DockCatalog.restartProcess(for: "click-to-desktop"))
            preference("desktop-widgets", title: "Hide desktop widgets", module: NotchcastCore.dockTweaks,
                       feature: .dockTweaks, writes: DockCatalog.writes["desktop-widgets"] ?? [],
                       restart: DockCatalog.restartProcess(for: "desktop-widgets"))
        }
    }

    private var appleAppsRows: some View {
        Group {
            featureSwitch(.appleAppsTweaks)
            profile(.gameCenter, title: "Restrict gaming")
            profile(.iPhoneMirroring, title: "Restrict iPhone mirroring")
            profile(.musicService, title: "Restrict music service")
            profile(.bookstore, title: "Restrict book store")
        }
    }

    private var backupRows: some View {
        Group {
            featureSwitch(.iPhoneBackupTweaks)
            preference("automatic-backups", title: "Turn off iPhone auto backups",
                       module: NotchcastCore.iPhoneBackupTweaks, feature: .iPhoneBackupTweaks,
                       writes: IPhoneBackupPolicy.writes(automaticBackups: false), restart: nil)
            LabeledContent {
                Button("Reveal backup folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:
                        IPhoneBackupPolicy.backupDirectory(home: FileManager.default.homeDirectoryForCurrentUser).path)
                }
            } label: {
                SettingsRowTitle(.notchcastTweaksApps, "iPhone backup folder")
                Text(IPhoneBackupPolicy.backupDirectory(home: FileManager.default.homeDirectoryForCurrentUser).path)
            }
        }
    }

    private func featureSwitch(_ feature: NotchcastFeature) -> some View {
        Toggle(isOn: Binding(get: { preferences.isOn(feature) }, set: { enabled in
            Task { await module(feature).setFeature(feature, enabled: enabled) }
        })) {
            SettingsRowTitle(.notchcastTweaksApps, verbatim: feature.title)
            Text(feature.subtitle)
        }
    }

    private func module(_ feature: NotchcastFeature) -> TweaksModule {
        switch feature {
        case .typingTweaks: NotchcastCore.typingTweaks
        case .finderTweaks: NotchcastCore.finderTweaks
        case .dockTweaks: NotchcastCore.dockTweaks
        case .appleAppsTweaks: NotchcastCore.appleAppsTweaks
        default: NotchcastCore.iPhoneBackupTweaks
        }
    }

    private func profile(_ restriction: AppleAppsPolicy.Restriction, title: LocalizedStringResource) -> some View {
        Button {
            Task { await NotchcastCore.appleAppsTweaks.handOffProfile(restriction) }
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, title)
            Text("macOS requires your approval to install this restriction; remove it in System Settings.")
        }
        .settingsEnabled(preferences.isOn(.appleAppsTweaks) && !NotchcastCore.appleAppsTweaks.store.busy)
    }

    private func repeatPicker(_ identifier: String, title: LocalizedStringResource,
                              key: String, values: [Int]) -> some View {
        Picker(selection: Binding(get: {
            if case .integer(let value) = NotchcastCore.typingTweaks.store.plans[identifier]?.entries.first?.write.value {
                return value
            }
            return 0
        }, set: { value in
            Task { await NotchcastCore.typingTweaks.set(identifier,
                writes: [.init(key, .integer(value))], on: value != 0,
                title: String(localized: title), subtitle: subtitle(nil), restart: nil) }
        })) {
            Text("Original").tag(0)
            ForEach(values, id: \.self) { value in Text(value.formatted()).tag(value) }
        } label: {
            SettingsRowTitle(.notchcastTweaksApps, title)
            Text(subtitle(nil))
        }
        .settingsEnabled(preferences.isOn(.typingTweaks) && !NotchcastCore.typingTweaks.store.busy)
    }

    private func preference(_ identifier: String, title: LocalizedStringResource, module: TweaksModule,
                            feature: NotchcastFeature, writes: [TypingPreferencePlan.Write],
                            restart: String?) -> some View {
        Toggle(isOn: Binding(get: { module.store.plans[identifier] != nil }, set: { on in
            Task { await module.set(identifier, writes: writes, on: on,
                                    title: String(localized: title), subtitle: subtitle(restart), restart: restart) }
        })) {
            SettingsRowTitle(.notchcastTweaksApps, title)
            Text(subtitle(restart))
        }
        .settingsEnabled(preferences.isOn(feature) && !module.store.busy)
    }

    private func subtitle(_ restart: String?) -> String {
        switch restart {
        case "Finder": String(localized: "Changes Finder preferences and restarts Finder after confirmation.")
        case "Dock": String(localized: "Changes Dock preferences and restarts Dock after confirmation.")
        case "SystemUIServer": String(localized: "Changes screenshot preferences and restarts SystemUIServer after confirmation.")
        default: String(localized: "Changes system preferences after confirmation; some changes require signing out.")
        }
    }
}
