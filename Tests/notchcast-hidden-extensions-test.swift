// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
import Foundation

@main
struct HiddenExtensionsTest {
    static func main() throws {
        precondition(!SettingsSection.allCases.flatMap(\.tabs).contains(.extensions))
        precondition(SettingsTab(slug: "extensions") == nil)
        func source(_ path: String) throws -> String {
            try String(contentsOfFile: "Tinycast/" + path, encoding: .utf8)
        }
        let settings = try source("Features/Settings/AppSettings.swift")
        let property = settings.components(separatedBy: "var extensionsEnabled: Bool {")[1]
            .components(separatedBy: "var extensionsShowInLauncher")[0]
        precondition(property.contains("get { false }") && property.contains("set { }"))
        let catalog = try source("Features/Settings/SettingsSearchCatalog.swift")
        precondition(!catalog.components(separatedBy: "private static let general")[0]
            .contains("+ extensions"))
        for (path, gate) in [
            ("Features/Launcher/Service/AppIndex.swift", "guard settings?.extensionsEnabled == true"),
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
        precondition(hotkeys.contains("var boundExtensionCommandEntryIDs: [String] {\n        []"))
        let coordinator = try source("Features/Extensions/UI/ExtensionCoordinator.swift")
        precondition(coordinator.contains("func showStoreInstall(_ install: ExtensionDeepLink.StoreInstall) {\n        guard settings.extensionsEnabled else { return }"))
        let core = try source("App/AppCore.swift")
        precondition(core.contains("if settings.extensionsEnabled { extensions.start("))
        print("Hidden Extensions: settings, discovery, entry points and startup passed")
    }
}
