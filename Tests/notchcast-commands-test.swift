// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/AppEntry+NotchcastCommands.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandCatalog.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
// notchcast-sources: Tinycast/Features/DeepLinks/Model/DeepLink.swift
// notchcast-sources: Tinycast/Features/DeepLinks/Model/DeepLinkInput.swift
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
struct CustomWindowSize: FixtureEntry, Equatable, Sendable {
    init?(linkFields: [String: String]) { return nil }
}
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

@MainActor final class CommandFixture {
    static let shared = CommandFixture()
    var commandsAvailable = true
    var runs = 0
    func toggle() { runs += 1 }
}

enum AgentSessionsModule {
    static let refreshCommand = NotchcastCommand(
        slug: "refresh-agent-session-logs", name: "Refresh Agent Session Logs", sfSymbol: "arrow.clockwise", run: {})
}

extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        NotchcastCommand(slug: "theme", name: "Theme", sfSymbol: "test", legacyID: "command:theme", run: {}),
        NotchcastCommand(slug: "future", name: "Future", sfSymbol: "test", legacyID: "command:future-legacy", run: {}),
        NotchcastCommand(
            slug: "toggle-island", name: "Test command", sfSymbol: "test",
            feature: .island,
            legacyID: "command:toggle-island",
            isEnabled: { CommandFixture.shared.commandsAvailable },
            run: { CommandFixture.shared.toggle() }),
        NotchcastCommand(slug: "convert-files", name: "convert-files", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "download-video", name: "download-video", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "download-audio", name: "download-audio", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "download-youtube-transcript", name: "download-youtube-transcript", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "save-webpage-as-markdown", name: "save-webpage-as-markdown", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "add-links-to-distill", name: "add-links-to-distill", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "run-distill", name: "run-distill", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "convert-distill-folder", name: "convert-distill-folder", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "open-downloads-folder", name: "open-downloads-folder", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "open-distill-folder", name: "open-distill-folder", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "compress-video", name: "compress-video", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "make-gif", name: "make-gif", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "compress-image", name: "compress-image", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "resize-image", name: "resize-image", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "extract-text", name: "extract-text", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "run-host-command", name: "run-host-command", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "list-commands", name: "list-commands", sfSymbol: "test", run: {}),
        NotchcastCommand(slug: "open-remote-mac-terminal", name: "Terminal", sfSymbol: "terminal", run: {}),
        NotchcastCommand(slug: "send-to-remote-mac", name: "Send", sfSymbol: "paperplane", run: {}),
        NotchcastCommand(slug: "update-remote-mac", name: "Update", sfSymbol: "arrow.clockwise", run: {}),
        AgentSessionsModule.refreshCommand,
    ]
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let paletteCoordinator = PaletteCoordinator()
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
        var failures = 0
        for entry in NotchcastCommandCatalog.entries {
            let expected = HotKeyAction.notchcastCommand(entryID: entry.id)
            if HotKeyAction(entryID: entry.id) != expected {
                print("FAIL: catalog row \(entry.id) must resolve to notchcastCommand")
                failures += 1
            }
            assert(expected.defaultsKey == "hotkey." + entry.id)
        }
        let themeURL = URL(string: "notchcast://command/theme")!
        if DeepLink(url: themeURL, scheme: "notchcast") != .entry(.notchcastCommand(entryID: "command:theme"), .none) {
            print("FAIL: notchcast://command/theme must parse as a fork command")
            failures += 1
        }
        if failures > 0 { exit(1) }
        print("PASS: every catalog row resolves, legacy defaults keys preserved, Theme deeplink parses")
        assert(Set(commands.map(\.id)).count == commands.count)
        assert(commands.allSatisfy { $0.id.hasPrefix("command:nc-") })
        assert(commands.allSatisfy { command in CommandCatalog.all.contains { $0.id == command.entry.id } })
        assert(CommandCatalog.entries(ownedBy: .notchcast).count == commands.count + SettingsTab.notchcast.ownedCommands.count)
        assert(CommandCatalog.entries(ownedBy: .notchcast).allSatisfy { $0.hotKeyAction != nil })
        assert(commands.allSatisfy { $0.entry.symbolName == $0.sfSymbol })
        let islandCommand = commands.first { $0.legacyID == "command:toggle-island" }!
        let action = HotKeyAction.notchcastCommand(entryID: islandCommand.entry.id)
        assert(action.defaultsKey == "hotkey.command:toggle-island")
        assert(HotKeyAction(entryID: islandCommand.entry.id) == action)
        assert(action.entryID == islandCommand.entry.id)
        let island = CommandFixture.shared
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
        NotchcastCommandCatalog.perform(islandCommand.entry.id)
        assert(palette.hideCalls == 0 && island.runs == 2)
        palette.isVisible = true
        assert(NotchcastCommandCatalog.dispatch(islandCommand.id, dismiss: {
            palette.hidePalette(restoreFocus: false)
        }))
        assert(palette.hideCalls == 1 && !palette.restoredFocus && island.runs == 3)
        palette.isVisible = true
        NotchcastCommandCatalog.perform(islandCommand.entry.id)
        assert(palette.hideCalls == 2 && !palette.restoredFocus && island.runs == 4)
        print("PASS: unique prefixed IDs, catalog, owner, legacy ID, disabled visibility and dispatch")
    }
}
