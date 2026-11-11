// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyBinding.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HyperKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/KeyShortcut.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/HotKeyManager.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift
// notchcast-sources: Tests/hotkey-dispatch-fixtures.swift
// notchcast-kit: core command
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/HotKeyManager+NotchcastCommands.swift
import Carbon.HIToolbox
import Foundation

@MainActor final class AppCore {
    static let shared = AppCore()
    var paletteCoordinator: AppCore { self }
    var isVisible = false
    func hidePalette(restoreFocus: Bool) {}
}
extension NotchcastCommandCatalog {
    nonisolated(unsafe) static var all: [NotchcastCommand] = []
}

@main struct HotKeysOffTest {
    @MainActor static var failures = 0
    @MainActor static var checks = 0

    @MainActor static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    @MainActor static func main() throws {
        // Preferences live in the dev app's domain; run in a throwaway home so nothing is left behind.
        if ProcessInfo.processInfo.environment["NC_HOTKEYS_OFF_HOME"] == nil {
            let home = FileManager.default.temporaryDirectory.appending(path: "nc-hotkeys-off-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let child = Process()
            child.executableURL = URL(filePath: CommandLine.arguments[0])
            child.environment = ProcessInfo.processInfo.environment.merging(
                ["NC_HOTKEYS_OFF_HOME": home.path, "HOME": home.path, "CFFIXED_USER_HOME": home.path]) { $1 }
            try child.run()
            child.waitUntilExit()
            exit(child.terminationStatus)
        }
        precondition(NSHomeDirectory() == ProcessInfo.processInfo.environment["NC_HOTKEYS_OFF_HOME"])
        let domain = "notchcast.hotkeys-off-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = NotchcastPreferences.shared
        for feature in NotchcastFeature.allCases { preferences.set(feature, true) }
        let owner = NotchcastFeature.allCases.first { !$0.dependencies.isEmpty }!
        let dependency = owner.dependencies[0]
        let command = NotchcastCommand(slug: "fixture", name: "Fixture", sfSymbol: "test", feature: owner, run: {})
        let orphan = NotchcastCommand(slug: "orphan", name: "Orphan", sfSymbol: "test", run: {})
        NotchcastCommandCatalog.all = [command, orphan]
        let action = HotKeyAction.notchcastCommand(entryID: command.id)
        let orphanAction = HotKeyAction.notchcastCommand(entryID: orphan.id)
        let combo = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: kVK_ANSI_J, carbonModifiers: cmdKey | optionKey))
        let orphanCombo = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey | optionKey))
        func registered(_ action: HotKeyAction) -> Bool { HotKeyCenter.current?.entries[action.defaultsKey] != nil }

        let manager = HotKeyManager(defaults: defaults)
        manager.start(customCommandIDs: [], quicklinkIDs: [], windowLayoutIDs: [],
                      windowRoomIDs: [], customWindowSizeIDs: [], quickActionIDs: [])
        preferences.commandAvailabilityChanged = { manager.syncNotchcastCommands() }
        manager.setBinding(combo, for: action)
        manager.setBinding(orphanCombo, for: orphanAction)
        check("an enabled feature's combo registers", registered(action))
        check("a command without a feature never registers", !registered(orphanAction))

        preferences.set(owner, false)
        check("switching the feature off releases its combo", !registered(action))
        check("the saved binding survives the switch", manager.binding(for: action) == combo)
        check("a disabled command still reserves its combo",
              manager.conflictOwner(of: combo, excluding: .togglePalette) == "Fixture")
        preferences.set(owner, true)
        check("switching the feature on registers it again", registered(action))

        preferences.set(dependency, false)
        check("a dependency switched off releases the combo", !registered(action))
        preferences.set(dependency, true)
        check("the dependency switched on restores it", registered(action))

        preferences.set(owner, false)
        let relaunched = HotKeyManager(defaults: defaults)
        relaunched.start(customCommandIDs: [], quicklinkIDs: [], windowLayoutIDs: [],
                         windowRoomIDs: [], customWindowSizeIDs: [], quickActionIDs: [])
        preferences.commandAvailabilityChanged = { relaunched.syncNotchcastCommands() }
        check("a feature off at launch registers nothing", !registered(action))
        preferences.set(owner, true)
        check("turning it on after launch registers it", registered(action))

        let hyper = HotKeyBinding.combo(KeyShortcut(
            carbonKeyCode: kVK_ANSI_J, carbonModifiers: cmdKey | optionKey | controlKey))
        let equivalentID = "secureInputEquivalent." + action.defaultsKey
        relaunched.setBinding(hyper, for: action)
        relaunched.setSecureInputEquivalents(includesShift: false)
        check("Secure Input registers an enabled command's equivalent",
              HotKeyCenter.current?.entries[equivalentID] != nil)
        preferences.set(owner, false)
        check("switching off releases the Secure Input equivalent",
              HotKeyCenter.current?.entries[equivalentID] == nil)
        check("Secure Input keeps the disabled command's saved Hyper binding",
              relaunched.binding(for: action) == hyper)
        relaunched.setSecureInputEquivalents(includesShift: nil)
        relaunched.setSecureInputEquivalents(includesShift: false)
        check("entering Secure Input while off registers no equivalent",
              HotKeyCenter.current?.entries[equivalentID] == nil)
        preferences.set(owner, true)
        check("switching on restores the Secure Input equivalent",
              HotKeyCenter.current?.entries[equivalentID] != nil)
        preferences.set(dependency, false)
        check("switching off a dependency releases the Secure Input equivalent",
              HotKeyCenter.current?.entries[equivalentID] == nil)
        preferences.set(dependency, true)
        check("restoring a dependency restores the Secure Input equivalent",
              HotKeyCenter.current?.entries[equivalentID] != nil)

        let modifier = HotKeyBinding.modifier(.rightOption)
        relaunched.setBinding(modifier, for: action)
        check("an enabled command reserves its modifier tap", ModifierTapMonitor.bound.contains(modifier))
        preferences.set(owner, false)
        check("switching off releases the modifier tap", !ModifierTapMonitor.bound.contains(modifier))
        check("a disabled command still reserves its modifier",
              relaunched.conflictOwner(of: modifier, excluding: .togglePalette) == "Fixture")
        preferences.set(owner, true)
        check("switching on restores the modifier tap", ModifierTapMonitor.bound.contains(modifier))
        check("switching on restores the modifier conflict",
              relaunched.conflictOwner(of: modifier, excluding: .togglePalette) == "Fixture")

        print("\(checks) hotkeys-off checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
