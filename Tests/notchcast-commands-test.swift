// notchcast-sources: Tinycast/Features/Notchcast/Tools/NotchcastToolsCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Tools/NotchcastToolsLauncherCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadLauncherCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadCommands+Action.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/AppEntry+NotchcastCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandController+Command.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandCatalog.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
import Foundation
import Observation

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
    let appIndex = AppIndex()
    enum Tone { case danger }
    func showMessage(_ text: String, tone: Tone) {}
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

@MainActor final class AppIndex {
    func refreshNotchcastCommands() {}
}
@MainActor @Observable final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    private var off: Set<NotchcastFeature> = []
    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }
    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        if enabled { off.remove(feature) } else { off.insert(feature) }
    }
}
@MainActor final class DownloadsModule {
    var commandTask: Task<Void, Never>?
}
@MainActor final class DistillModule {
    var commandTask: Task<Void, Never>?
}
@MainActor struct NotchcastDownloadCommands {
    let downloads: DownloadsModule
    let distill: DistillModule
    let preferences: NotchcastPreferences
    let status: (String) -> Void
    func perform(_ action: Action) async {}
}

@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }

@main @MainActor struct NotchcastCommandsTest {
    static func main() {
        let commands = NotchcastCommandCatalog.all
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
        let preferences = NotchcastPreferences.shared
        let switches: [NotchcastFeature] = [.downloads, .distill, .distillConvert]
        let previous = switches.map { preferences.isOn($0) }
        defer { for (feature, enabled) in zip(switches, previous) { preferences.set(feature, enabled) } }
        for feature in switches { preferences.set(feature, true) }
        let expected: [(String, NotchcastFeature)] = [
            ("command:nc-download-video", .downloads),
            ("command:nc-download-audio", .downloads),
            ("command:nc-download-youtube-transcript", .downloads),
            ("command:nc-save-webpage-as-markdown", .downloads),
            ("command:nc-add-links-to-distill", .distill),
            ("command:nc-run-distill", .distill),
            ("command:nc-convert-distill-folder", .distillConvert),
            ("command:nc-open-downloads-folder", .downloads),
            ("command:nc-open-distill-folder", .distill),
        ]
        assert(commands.count == expected.count + 9)
        for (id, feature) in expected {
            let command = NotchcastCommandCatalog.command(for: id)!
            assert(command.owner == .notchcast && !command.sfSymbol.isEmpty)
            assert(command.isEnabled())
            preferences.set(feature, false)
            assert(!command.isEnabled())
            assert(!CommandCatalog.all.filter { NotchcastCommandCatalog.isEnabled($0.id) }.contains { $0.id == id })
            assert(NotchcastCommandCatalog.dispatch(id, dismiss: { preconditionFailure("Disabled command dismissed") }))
            preferences.set(feature, true)
        }
        preferences.set(.distill, false)
        assert(!NotchcastDownloadLauncherCommands.convert.isEnabled())
        print("PASS: nine Downloads/Distill registrations, owners, switch visibility and disabled dispatch")
        print("PASS: unique prefixed IDs, catalog, owner, legacy ID, disabled visibility and dispatch")
    }
}
