// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden+Tabs.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
import Foundation

@main
struct HiddenFeaturesTest {
    static func main() throws {
        precondition(!SettingsSection.allCases.flatMap(\.tabs).contains(.extensions))
        precondition(SettingsTab(slug: "extensions") == nil)
        let visible = SettingsSection.allCases.flatMap(\.tabs)
        let hiddenTabs: [SettingsTab] = [.extensions, .fallbacks, .appleShortcuts, .about, .backup]
        precondition(NotchcastHidden.tabs == Set(hiddenTabs))
        precondition(NotchcastHidden.commands == ["command:support", "command:import-from-raycast"])
        precondition(!NotchcastHidden.fallbacksEnabled && !NotchcastHidden.supportEnabled)
        for tab in hiddenTabs {
            precondition(!visible.contains(tab), "Visible hidden tab: \(tab.slug)")
            precondition(SettingsTab(slug: tab.slug) == nil)
            precondition(!SettingsSearchCatalog.entries.contains { $0.tab == tab })
        }
        precondition(SettingsSection.advanced.tabs.isEmpty)
        for (title, anchor) in [("Sync settings file", SettingsAnchor.notchcastBackupSettingsFile),
                                ("Export Backup", .notchcastBackupExport), ("Backup File", .notchcastBackupImport)] {
            precondition(anchor.tab == .notchcastBackups)
            precondition(SettingsSearchCatalog.results(for: title).contains { $0.anchor == anchor })
        }
        precondition(NotchcastSettingsModule.module(of: .settingsBackup).visibleGroups.contains {
            $0.items.contains { $0.feature == .settingsBackup }
        })
        print("Hidden features: inventory, settings and discovery passed")
    }
}
