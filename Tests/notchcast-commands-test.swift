// notchcast-sources: Tinycast/Features/LiveTimer/LiveTimerCommands.swift
// notchcast-sources: Tinycast/Features/LiveDay/DayCommands.swift
// notchcast-sources: Tinycast/Features/LowDisk/LowDiskCommands.swift
// notchcast-sources: Tinycast/Features/SystemNotices/SystemNoticesCommands.swift
// notchcast-sources: Tinycast/Features/QuitProtection/QuitProtectionCommands.swift
// notchcast-sources: Tinycast/Features/Appearance/AppearanceCommands.swift
// notchcast-sources: Tinycast/Features/SystemLevels/SystemLevelsCommands.swift
// notchcast-sources: Tinycast/Features/DisplayBrightness/DisplayBrightnessCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/AppEntry+NotchcastCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandController+Command.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandCatalog.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
import Foundation

enum SettingsTab: CaseIterable, Sendable {
    case general, commands, quicklinks, ai, quickActions, fileSearch, notes, snippets, navigation
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
    func open(page: IslandPage) { runs += 1 }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let paletteCoordinator = PaletteCoordinator()
    let settings = Settings()
    let settingsCoordinator = SettingsCoordinator()
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

enum IslandPage { case day }
enum NotchcastFeature { case island, liveTimers, dayWeather, dayMarkets, lowDiskWarning, systemNotices, quitProtection, displayBrightness, volumeLevels }
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = true
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}
@MainActor final class Settings { var calendarEnabled = true }
@MainActor final class SettingsCoordinator { func showSettings(tab: SettingsTab) {} }
@MainActor enum NotchcastCore {
    static let timers = LiveTimerModule()
    static let lowDisk = LowDiskModule()
    static let systemNotices = SystemNoticesModule()
    static let systemLevels = SystemLevelsModule()
}
@MainActor final class LiveTimerModule { let store = TimerFixture() }
@MainActor final class TimerFixture {
    struct Entry { let id: UUID }
    var ringing: [Entry] = []
    var nextTimer: Entry?
    var starts = 0
    var cancelled: UUID?
    func start() { starts += 1 }
    func cancel(_ id: UUID) { cancelled = id }
}
@MainActor final class LowDiskModule { let manager = RefreshFixture() }
@MainActor final class SystemNoticesModule { let manager = RefreshFixture() }
@MainActor final class RefreshFixture {
    var calls = 0
    func refresh() { calls += 1 }
    func refreshTailscale() { calls += 1 }
}
@MainActor final class QuitProtectionModule {}
@MainActor final class SystemLevelsModule { let service = AudioFixture() }
@MainActor final class AudioFixture {
    enum Command { case setVolume(Double) }
    enum Result { case fallbackToNativeKeys }
    var isRunning = false
    func apply(_ command: Command) async -> Result { .fallbackToNativeKeys }
}
extension AppCore { func showMessage(_ message: String) {} }

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
        for command in commands.dropFirst() {
            assert(HotKeyAction(entryID: command.id) == .notchcastCommand(entryID: command.id))
            NotchcastPreferences.shared.enabled = false
            if command.id != "command:nc-appearance" && command.id != "command:nc-day-calendar" {
                assert(!command.isEnabled())
            }
            NotchcastPreferences.shared.enabled = true
        }
        NotchcastCommandCatalog.perform("command:nc-start-timer")
        assert(NotchcastCore.timers.store.starts == 1)
        let timerID = UUID()
        NotchcastCore.timers.store.nextTimer = .init(id: timerID)
        NotchcastCommandCatalog.perform("command:nc-stop-timer")
        assert(NotchcastCore.timers.store.cancelled == timerID)
        NotchcastCommandCatalog.perform("command:nc-check-disk-space")
        assert(NotchcastCore.lowDisk.manager.calls == 1)
        NotchcastCommandCatalog.perform("command:nc-check-tailscale")
        assert(NotchcastCore.systemNotices.manager.calls == 1)
        print("PASS: unique prefixed IDs, catalog, owner, legacy ID, disabled visibility and dispatch")
    }
}
