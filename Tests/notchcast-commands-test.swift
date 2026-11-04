// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/AppEntry+NotchcastCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandController+Command.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule+Command.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule+Command.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
import AppKit
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
    func showMessage(_ message: String, tone: Tone) {}
    enum Tone { case danger }
}

enum Feature { case colorPicker, screenshot }
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var disabled: Set<Feature> = []
    func isOn(_ feature: Feature) -> Bool { !disabled.contains(feature) }
}
@MainActor enum NotchcastCore {
    static let colorPicker = ColorPickerModule()
    static let screenshot = ScreenshotModule()
}
@MainActor final class ColorPickerModule {
    var runs = 0
    func pick(completion: (Bool) -> Void) { runs += 1; completion(true) }
}
@MainActor final class ScreenshotModule {
    enum Request { case display(UInt32) }
    var commandTask: Task<Void, Never>?
    func capture(_ request: Request) async throws -> URL? { nil }
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
        for id in ["command:nc-pick-color", "command:nc-screenshot-display"] {
            assert(commands.contains { $0.id == id })
            assert(HotKeyAction(entryID: id) == .notchcastCommand(entryID: id))
        }
        NotchcastPreferences.shared.disabled = [.colorPicker, .screenshot]
        for id in ["command:nc-pick-color", "command:nc-screenshot-display"] {
            assert(!NotchcastCommandCatalog.isEnabled(id))
            assert(NotchcastCommandCatalog.dispatch(id, dismiss: { fatalError("Disabled command dismissed") }))
        }
        NotchcastPreferences.shared.disabled = []
        assert(NotchcastCommandCatalog.dispatch("command:nc-pick-color", dismiss: {}))
        assert(NotchcastCore.colorPicker.runs == 1)
        assert(Set(commands.map(\.id)).count == commands.count)
        assert(commands.allSatisfy { $0.id.hasPrefix("command:nc-") })
        assert(commands.allSatisfy { command in CommandCatalog.all.contains { $0.id == command.entry.id } })
        assert(CommandCatalog.entries(ownedBy: .notchcast).count == commands.count)
        assert(CommandCatalog.entries(ownedBy: .notchcast).allSatisfy { $0.hotKeyAction != nil })
        assert(commands.allSatisfy { $0.entry.symbolName == $0.sfSymbol })
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
        NotchcastCommandCatalog.perform("command:toggle-island")
        assert(palette.hideCalls == 0 && island.runs == 2)
        palette.isVisible = true
        NotchcastCommandCatalog.perform("command:toggle-island")
        assert(palette.hideCalls == 1 && !palette.restoredFocus && island.runs == 3)
        print("PASS: unique prefixed IDs, catalog, owner, legacy ID, disabled visibility and dispatch")
    }
}
