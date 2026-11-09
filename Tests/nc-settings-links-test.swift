// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-reads: Tinycast/Features/Notchcast/Settings/Tree/NotchcastBackupGroups.swift
import Foundation

@main
struct NotchcastSettingsLinksTests {
    static func main() throws {
        for module in NotchcastSettingsModule.allCases {
            precondition(SettingsTab(slug: module.slug) == module.tab)
            precondition(NotchcastSettingsModule(tab: module.tab) == module)
        }
        precondition(SettingsTab(slug: "notchcast") == NotchcastSettingsModule.island.tab)
        precondition(SettingsSearchCatalog.results(for: "caps lock").first?.tab == .general)
        for entry in SettingsSearchCatalog.notchcast where entry.target == nil {
            precondition(!SettingsTab.allCases.contains {
                NotchcastSettingsModule(tab: $0) == nil && $0.title == entry.title
            }, "Fork pane duplicates an upstream search identity")
        }
        for feature in NotchcastFeature.allCases {
            let anchor = SettingsAnchor.notchcast(feature: feature)
            precondition(anchor.tab == NotchcastSettingsModule.module(of: feature).tab)
            let entries = SettingsSearchCatalog.notchcast.filter {
                guard case .row = $0.target else { return false }
                return $0.title == feature.title
            }
            if feature.isWired {
                precondition(!entries.isEmpty, "Missing search entry: \(feature)")
                precondition(entries.allSatisfy { $0.tab == anchor.tab }, "Wrong module: \(feature)")
            } else {
                precondition(entries.isEmpty, "Unwired switch in search: \(feature)")
            }
        }
        let anchors: [(SettingsAnchor, NotchcastFeature)] = [
            (.notchcastAppearance, .appearance),
            (.notchcastClean, .cleanJunk),
            (.notchcastCleaning, .cleaningMode),
            (.notchcastAppUpdates, .appUpdates),
            (.notchcastMacUpdate, .macUpdate),
            (.notchcastTweaksApps, .typingTweaks),
            (.notchcastTasks, .tasks),
            (.notchcastArchives, .archives),
            (.notchcastBuildStats, .buildStats),
            (.notchcastAlerts, .monitorAlerts),
            (.notchcastAlertCPU, .monitorAlerts),
            (.notchcastAlertTemperature, .monitorAlerts),
            (.notchcastAlertMemory, .monitorAlerts),
            (.notchcastAlertDisk, .monitorAlerts),
            (.notchcastAlertBattery, .monitorAlerts),
            (.notchcastAccessories, .accessoryBatteries),
            (.notchcastChargePercent, .batteryChargeLimit),
            (.notchcastAwakeDuration, .keepAwake),
            (.notchcastMonitor, .systemMonitor),
            (.notchcastFanMode, .fanControl),
            (.notchcastIsland, .island),
            (.notchcastOptions, .islandHoverOpen),
            (.notchcastLauncher, .launcherFromIsland),
            (.notchcastSystem, .greenMaximize),
            (.notchcastActivities, .dayCalendar),
            (.notchcastMusic, .musicNowPlaying),
            (.notchcastSpotify, .spotifyConnect),
            (.notchcastMicrophone, .microphoneMute),
            (.notchcastBrightness, .displayBrightness),
            (.notchcastQuitProtection, .quitProtection),
            (.notchcastTimers, .liveTimers),
            (.notchcastDay, .dayCalendar),
            (.notchcastTweaks, .startupItems),
            (.notchcastDownloads, .downloads),
            (.notchcastLauncherTools, .githubSearch),
            (.notchcastAIUsage, .machLink),
            (.notchcastTorrents, .torrents),
            (.notchcastPaste, .pastePlain),
            (.notchcastRemoteMac, .machRemote),
            (.notchcastFinder, .finderRename),
            (.notchcastCaptureAndDictation, .screenshot),
        ]
        for (anchor, feature) in anchors {
            let module = NotchcastSettingsModule.module(of: feature)
            precondition(anchor.tab == module.tab)
            precondition(module.groups.contains { $0.title.resolved() == anchor.title })
        }
        for entry in SettingsSearchCatalog.notchcast {
            let module = NotchcastSettingsModule(tab: entry.tab)!
            if let anchor = entry.anchor {
                if [.notchcastBackupSettingsFile, .notchcastBackupExport, .notchcastBackupImport].contains(anchor) {
                    precondition(module == .backups)
                    let source = try String(contentsOfFile:
                        "Tinycast/Features/Notchcast/Settings/Tree/NotchcastBackupGroups.swift", encoding: .utf8)
                    precondition(source.contains("SettingsSectionHeader(.notchcastBackup"))
                    continue
                }
                precondition(module.groups.contains { $0.title.resolved() == anchor.title })
            }
        }
        print("PASS: 17 module slugs, all feature search destinations and named anchors")
    }
}

