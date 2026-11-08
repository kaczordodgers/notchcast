// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastHidden+Tabs.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-reads: notchcast/docs/hidden.md Tinycast/App/AppCore.swift Tinycast/App/MenuBarItem.swift
// notchcast-reads: Tinycast/Features/Settings/*.swift Tinycast/Windows/About/AboutView.swift
// notchcast-reads: Tinycast/Features/Notchcast/Settings/Tree/NotchcastBackupGroups.swift
// notchcast-reads: Tinycast/Features/AppleShortcuts/UI/AppleShortcutCoordinator.swift
// notchcast-reads: Tinycast/Features/Launcher/Model/CommandCatalog.swift
// notchcast-reads: Tinycast/Features/Launcher/UI/LauncherCoordinator.swift
// notchcast-reads: Tinycast/Features/Launcher/UI/AppActionsMenu.swift
// notchcast-reads: Tinycast/Features/Launcher/Keys/LauncherScreen+AliasSpace.swift
// notchcast-reads: Tinycast/Features/Launcher/Service/FallbackStore.swift
// notchcast-reads: Tinycast/Features/Support/UI/SupportCoordinator.swift
// notchcast-reads: Tinycast/Features/Support/Service/SupportReminderStore.swift
// notchcast-reads: Tinycast/Features/Extensions/Service/ExtensionManager.swift
// notchcast-reads: Tinycast/Features/Extensions/UI/ExtensionCoordinator.swift Tinycast/Palette/RootPaletteView.swift
import Foundation

@main
struct HiddenFeaturesTest {
    static func main() throws {
        precondition(!SettingsSection.allCases.flatMap(\.tabs).contains(.extensions))
        precondition(SettingsTab(slug: "extensions") == nil)
        let document = try String(contentsOfFile: "notchcast/docs/hidden.md", encoding: .utf8)
        let rows = document.split(separator: "\n").filter { $0.hasPrefix("| Hidden |") }
        precondition(rows.count == 7)
        let visible = SettingsSection.allCases.flatMap(\.tabs)
        for row in rows {
            let cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let slug = cells[2]
            if slug != "none" {
                let tab = SettingsTab.allCases.first { $0.slug == slug }!
                precondition(!visible.contains(tab), "Visible hidden tab: \(slug)")
                precondition(SettingsTab(slug: slug) == nil)
                precondition(!SettingsSearchCatalog.entries.contains { $0.tab == tab })
            }
            if cells[3] != "none" {
                precondition(NotchcastHidden.commands.contains(cells[3]))
            }
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
        func source(_ path: String) throws -> String {
            try String(contentsOfFile: "Tinycast/" + path, encoding: .utf8)
        }
        let settings = try source("Features/Settings/AppSettings.swift")
        let backups = try source("Features/Notchcast/Settings/Tree/NotchcastBackupGroups.swift")
        precondition(backups.contains("SettingsRowTitle(.notchcastBackupSettingsFile, \"Sync settings file\")"))
        precondition(backups.contains("get: { core.settings.settingsFileEnabled }"))
        precondition(!backups.contains("settingsFileEnabled ="))
        let sidebar = try source("Features/Settings/SettingsSidebarView.swift")
        precondition(sidebar.contains("SettingsSection.allCases.filter { !$0.tabs.isEmpty }"))
        let property = settings.components(separatedBy: "var extensionsEnabled: Bool {")[1]
            .components(separatedBy: "var extensionsShowInLauncher")[0]
        precondition(property.contains("get { false }") && property.contains("set { }"))
        let catalog = try source("Features/Settings/SettingsSearchCatalog.swift")
        precondition(catalog.contains("filter { !NotchcastHidden.tabs.contains($0.tab) }"))
        let menu = try source("App/MenuBarItem.swift")
        precondition(menu.contains("Button(\"About \\(appName)\") { AppCore.shared.settingsCoordinator.showAbout() }"))
        precondition(!menu.contains("showSupport"))
        let settingsCoordinator = try source("Features/Settings/SettingsCoordinator.swift")
        let detail = try source("Features/Settings/SettingsDetailView.swift")
        let about = try source("Windows/About/AboutView.swift")
        precondition(settingsCoordinator.contains("showSettings(tab: .about)"))
        precondition(detail.contains("case .about: AboutView()"))
        precondition(about.contains("Released under AGPL-3.0"))
        precondition(about.contains("if NotchcastHidden.supportEnabled { support }"))
        let shortcuts = try source("Features/AppleShortcuts/UI/AppleShortcutCoordinator.swift")
        precondition(shortcuts.contains("guard settings.appleShortcutsEnabled else"))
        let commands = try source("Features/Launcher/Model/CommandCatalog.swift")
        precondition(commands.contains("filter { !NotchcastHidden.commands.contains($0.rawValue) }"))
        let launcher = try source("Features/Launcher/UI/LauncherCoordinator.swift")
        precondition(launcher.contains("guard !NotchcastHidden.commands.contains(id.rawValue) else { return }"))
        for name in ["appleShortcutsEnabled", "supportRemindersEnabled"] {
            let body = settings.components(separatedBy: "var \(name): Bool {")[1]
                .components(separatedBy: "\n    }")[0]
            precondition(body.contains("get { false }") && body.contains("set { }"))
        }
        precondition(!NotchcastHidden.fallbacksEnabled && !NotchcastHidden.supportEnabled)
        let fallback = try source("Features/Launcher/Service/FallbackStore.swift")
        let support = try source("Features/Support/UI/SupportCoordinator.swift")
        let reminder = try source("Features/Support/Service/SupportReminderStore.swift")
        precondition(fallback.contains("NotchcastHidden.fallbacksEnabled &&"))
        precondition(support.contains("guard NotchcastHidden.supportEnabled else { return }"))
        precondition(reminder.contains("guard NotchcastHidden.supportEnabled else { return }"))
        for (path, gate) in [
            ("Features/Extensions/Service/ExtensionManager.swift", "guard isEnabled, showsInLauncher else"),
            ("Features/Launcher/UI/LauncherCoordinator.swift", "guard core.settings.extensionsEnabled"),
            ("Features/Launcher/UI/AppActionsMenu.swift", "&& core.settings.extensionsEnabled"),
            ("Features/Launcher/Keys/LauncherScreen+AliasSpace.swift", "guard core.settings.extensionsEnabled"),
            ("Palette/RootPaletteView.swift", "guard settings.extensionsEnabled, vm.mode"),
            ("Features/Extensions/UI/ExtensionCoordinator.swift", "func showStoreInstall")
        ] {
            let text = try source(path)
            precondition(text.contains(gate))
        }
        let hotkeys = try source("Features/HotKeys/Service/HotKeyManager.swift")
        precondition(hotkeys.contains("NotchcastHidden.commands.contains(id.rawValue) { return nil }"))
        precondition(hotkeys.contains("var boundExtensionCommandEntryIDs: [String] {\n        []"))
        let coordinator = try source("Features/Extensions/UI/ExtensionCoordinator.swift")
        precondition(coordinator.contains("func showStoreInstall(_ install: ExtensionDeepLink.StoreInstall) {\n        guard settings.extensionsEnabled else { return }"))
        let core = try source("App/AppCore.swift")
        precondition(core.contains("if settings.extensionsEnabled { extensions.start("))
        print("Hidden features: inventory, settings, discovery, entry points and startup passed")
    }
}
