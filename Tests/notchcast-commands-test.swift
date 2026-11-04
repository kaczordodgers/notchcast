// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/AppEntry+NotchcastCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandController+Command.swift
// notchcast-sources: Tinycast/Features/Battery/Commands/BatteryModule+Command.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Commands/FanControl+Command.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandCatalog.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
import Foundation

enum SettingsTab: CaseIterable, Sendable {
    case commands, quicklinks, ai, quickActions, fileSearch, notes, snippets, navigation
    case windowManagement, clipboard, emoji, calendar, notchcast
}

struct AppEntry: Sendable {
    enum Kind { case command, quickAction }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    var settingsOwner: SettingsTab?
    var subtitle: String?
    var alternateTitles: [String] = []
    var symbolName: String?
    var hotKeyAction: HotKeyAction? { HotKeyAction(entryID: id) }
}

enum CommandID: String, CaseIterable {
    case createCustomCommand, searchCustomCommands, createQuicklink, searchQuicklinks
    case importQuicklinks, exportQuicklinks, quickAI, aiChat, fixGrammar, rewrite, translate, summarize
    case searchFiles, showNotes, createNote, searchNotes, searchSnippets, createSnippet
    case switchWindows, switchWindowsBackwards, searchMenuItems, createWindowLayout
    case captureWindowLayout, switchRoom, createRoom, clipboardHistory, pasteSequentially, searchEmoji
    case joinNextMeeting, mySchedule, createEvent, copyMeetingLink, openInCalendar, openInBrowser
    var isQueryDriven: Bool { self == .openInBrowser }
    var name: String { rawValue }
    var englishName: String { rawValue }
    var builtInQuickAction: String? { nil }
    var hotKeyAction: HotKeyAction? { .command(self) }
}

struct SystemAction {
    enum ID: String { case fixture }
    var id = ID.fixture
    var entryID: String { "system-action:fixture" }
}
struct WindowCommand {
    enum ID: String { case fixture }
    var id = ID.fixture
    var entryID: String { "window-command:fixture" }
}
enum SystemActionCatalog {
    static func action(forEntryID: String) -> SystemAction? { nil }
    static func action(id: SystemAction.ID) -> SystemAction { SystemAction() }
}
enum WindowCommandCatalog {
    static func command(forEntryID: String) -> WindowCommand? { nil }
    static func command(id: WindowCommand.ID) -> WindowCommand? { nil }
}
protocol FixtureEntry {}
extension FixtureEntry {
    static var entryIDPrefix: String { "fixture:" }
    static func id(fromEntryID: String) -> UUID? { nil }
}
enum CustomWindowSize: FixtureEntry {}
enum WindowLayout: FixtureEntry {}
enum Room: FixtureEntry {}
enum CustomQuickAction: FixtureEntry {}
enum CustomCommand: FixtureEntry {}
enum Quicklink: FixtureEntry {}
enum AppleShortcut: FixtureEntry {
    static func entryID(for id: UUID) -> String { entryIDPrefix + id.uuidString }
}
enum StoredSnippet {
    typealias ID = String
    static let entryIDPrefix = "snippet:"
    static func id(fromEntryID: String) -> String? { nil }
}

enum QuicklinkDestination {
    case web(URL)
    static func detect(_ query: String) -> Self? { nil }
}

@MainActor final class IslandController {
    static let shared = IslandController()
    var commandsAvailable = true
    var runs = 0
    func toggle() { runs += 1 }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let paletteCoordinator = PaletteCoordinator()
}

@MainActor final class BatteryModule {
    var runs = 0
    func toggleKeepAwake() { runs += 1 }
}

enum FanControl {
    enum Mode: String { case max, auto }
}

@MainActor enum NotchcastCore {
    static let battery = BatteryModule()
    static func setFanMode(_ mode: FanControl.Mode) { NotchcastPreferences.shared.fanMode = mode.rawValue }
}

@MainActor final class NotchcastPreferences {
    enum Feature: Hashable { case keepAwake, fanControl, systemMonitor }
    static let shared = NotchcastPreferences()
    var enabled: Set<Feature> = []
    var fanMode = "auto"
    func isOn(_ feature: Feature) -> Bool { enabled.contains(feature) }
}

@MainActor final class PaletteCoordinator {
    var isVisible = false
    var hideCalls = 0
    var restoredFocus = false
    func hidePalette(restoreFocus: Bool) {
        hideCalls += 1
        restoredFocus = restoreFocus
        isVisible = false
    }
}

@main @MainActor struct NotchcastCommandsTest {
    static func main() {
        let commands = NotchcastCommandCatalog.all
        assert(Set(commands.map(\.id)).count == commands.count)
        assert(commands.allSatisfy { $0.id.hasPrefix("command:nc-") })
        assert(commands.allSatisfy { command in CommandCatalog.all.contains { $0.id == command.entry.id } })
        assert(CommandCatalog.entries(ownedBy: .notchcast).count == commands.count)
        assert(CommandCatalog.entries(ownedBy: .notchcast).allSatisfy { $0.hotKeyAction != nil })
        assert(commands.allSatisfy { $0.entry.symbolName == $0.sfSymbol })
        let preferences = NotchcastPreferences.shared
        let ids = ["command:nc-keep-awake", "command:nc-fans-max", "command:nc-fans-auto"]
        for id in ids {
            assert(commands.filter { $0.id == id }.count == 1)
            assert(!NotchcastCommandCatalog.isEnabled(id))
            assert(NotchcastCommandCatalog.dispatch(id, dismiss: { assertionFailure() }))
        }
        assert(NotchcastCore.battery.runs == 0 && preferences.fanMode == "auto")
        preferences.enabled = [.keepAwake, .fanControl]
        assert(NotchcastCommandCatalog.isEnabled(ids[0]))
        assert(!NotchcastCommandCatalog.isEnabled(ids[1]))
        preferences.enabled.insert(.systemMonitor)
        for id in ids {
            assert(NotchcastCommandCatalog.isEnabled(id))
            NotchcastCommandCatalog.perform(id)
            if id == ids[1] { assert(preferences.fanMode == "max") }
        }
        assert(NotchcastCore.battery.runs == 1 && preferences.fanMode == "auto")
        preferences.enabled.remove(.fanControl)
        assert(!NotchcastCommandCatalog.isEnabled(ids[1]))
        assert(!NotchcastCommandCatalog.isEnabled(ids[2]))
        let action = HotKeyAction.notchcastCommand(entryID: commands[0].entry.id)
        assert(action.defaultsKey == "hotkey.command:toggle-island")
        assert(HotKeyAction(entryID: commands[0].entry.id) == action)
        assert(action.entryID == commands[0].entry.id)
        let island = IslandController.shared
        var dismissed = 0
        assert(NotchcastCommandCatalog.dispatch("command:toggle-island", dismiss: { dismissed += 1 }))
        assert(island.runs == 1 && dismissed == 1)
        island.commandsAvailable = false
        let visible = CommandCatalog.all.filter { NotchcastCommandCatalog.isEnabled($0.id) }
        assert(!visible.contains { $0.id == "command:toggle-island" })
        assert(NotchcastCommandCatalog.dispatch("command:nc-toggle-island", dismiss: { dismissed += 1 }))
        assert(island.runs == 1 && dismissed == 1)
        assert(!NotchcastCommandCatalog.dispatch("command:unknown", dismiss: {}))
        island.commandsAvailable = true
        let palette = AppCore.shared.paletteCoordinator
        NotchcastCommandCatalog.perform(commands[0].entry.id)
        assert(palette.hideCalls == 0 && island.runs == 2)
        palette.isVisible = true
        assert(NotchcastCommandCatalog.dispatch(commands[0].id, dismiss: {
            palette.hidePalette(restoreFocus: false)
        }))
        assert(palette.hideCalls == 1 && !palette.restoredFocus && island.runs == 3)
        palette.isVisible = true
        NotchcastCommandCatalog.perform(commands[0].entry.id)
        assert(palette.hideCalls == 2 && !palette.restoredFocus && island.runs == 4)
        print("PASS: unique prefixed IDs, catalog, owner, legacy ID, disabled visibility and dispatch")
    }
}
