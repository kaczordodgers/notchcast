// notchcast-sources: Tinycast/Features/Quicklinks/Model/Quicklink.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift
// notchcast-sources: Tinycast/Features/Snippets/Model/Snippet.swift
// notchcast-sources: Tinycast/Features/Snippets/Model/SnippetTemplateEngine.swift
import Foundation

@main
@MainActor
struct LauncherQuicklinksTests {
    static func main() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "launcher-quicklinks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try storage(at: scratch.appending(path: "library"))
        try refusedWrites(at: scratch.appending(path: "corrupt"))
        templates(home: scratch.path)
    }

    private static func storage(at directory: URL) throws {
        let store = QuicklinkStore(directory: directory)
        precondition(store.isAvailable)
        store.load()
        precondition(store.quicklinks.isEmpty)
        var changes = 0
        store.onChange = { _ in changes += 1 }
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = try store.add(
            Quicklink(
                name: "  Search  ", link: " https://example.com/?q={query} ",
                openWithBundleID: "com.example.browser", iconSymbol: "globe",
                createdAt: created))
        precondition(saved.name == "Search" && saved.link == "https://example.com/?q={query}")
        precondition(Quicklink.id(fromEntryID: saved.entryID) == saved.id)
        precondition(store.quicklink(entryID: saved.entryID) == saved)
        let originalCount = store.quicklinks.count
        expectError(.duplicateName) {
            _ = try store.add(Quicklink(name: "search", link: "https://other.example.com"))
        }
        expectError(.emptyName) {
            _ = try store.add(Quicklink(name: " \n", link: "https://example.com"))
        }
        expectError(.emptyLink) {
            _ = try store.add(Quicklink(name: "Empty", link: " "))
        }
        expectError(.unresolvableLink) {
            _ = try store.add(Quicklink(name: "Invalid", link: "not a destination"))
        }
        expectError(.invalidCharacter) {
            _ = try store.add(Quicklink(name: "Null\0Name", link: "https://example.com"))
        }
        precondition(store.quicklinks.count == originalCount && changes == 1)
        print("Verified launcher-quicklinks: upstream CRUD, stable identity, validation and duplicate refusal")

        var edited = saved
        edited.name = "Updated"
        edited.link = "https://example.com/search?q={query}"
        edited.showsInRootSearch = false
        try store.update(edited)
        try store.setEnabled(false, id: edited.id)
        precondition(store.enabled.isEmpty && store.quicklinks.count == 1)
        precondition(store.quicklink(id: edited.id)?.link == edited.link)
        try store.togglePinned(id: edited.id)
        let pinned = store.quicklink(id: edited.id)!
        precondition(pinned.isPinned && pinned.createdAt == created)
        let reopened = QuicklinkStore(directory: directory)
        reopened.load()
        var restored = reopened.quicklink(id: saved.id)!
        precondition(abs(restored.pinnedAt!.timeIntervalSince(pinned.pinnedAt!)) < 0.000001)
        restored.pinnedAt = pinned.pinnedAt
        precondition(restored == pinned)
        precondition(reopened.enabled.isEmpty)
        try reopened.setEnabled(true, id: edited.id)
        precondition(reopened.enabled.count == 1)
        precondition(reopened.quicklink(id: edited.id)?.showsInRootSearch == false)
        let duplicate = try reopened.duplicate(id: edited.id)
        precondition(duplicate.id != edited.id && duplicate.name != edited.name)
        precondition(duplicate.link == edited.link)
        try reopened.remove(id: edited.id)
        reopened.load()
        precondition(reopened.quicklink(id: edited.id) == nil && reopened.quicklinks.count == 1)
        try reopened.update(edited)
        precondition(reopened.quicklink(id: edited.id) == nil, "Stale drafts cannot recreate deleted rows")
        print("Verified launcher-quicklinks: temp SQLite reload, edits, enabled state, pinning and deletion")
    }

    private static func refusedWrites(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appending(path: "quicklinks.sqlite3")
        let original = Data("authored data that is not a database".utf8)
        try original.write(to: database)
        let store = QuicklinkStore(directory: directory)
        precondition(!store.isAvailable)
        expectError(.storageUnavailable) {
            _ = try store.add(Quicklink(name: "Refused", link: "https://example.com"))
        }
        let preserved = try Data(contentsOf: database)
        precondition(preserved == original, "Unavailable authored storage must never be discarded")
        print("Verified launcher-quicklinks: corrupt authored data preserved and writes refused")
    }

    private static func templates(home: String) {
        let context = SnippetTemplateEngine.ExpansionContext(
            clipboard: "", selection: "", now: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!)
        let template = "https://example.com/?q={query}"
        let missing = SnippetTemplateEngine.expand(text: template, context: context)
        precondition(missing.missingArguments.map(\.name) == ["Argument"])
        precondition(SnippetTemplateEngine.declaredArguments(in: template).count == 1)
        let expansion = SnippetTemplateEngine.expand(
            text: template, context: context, userArguments: ["Argument": "café & a/b?"],
            encoding: .percentEncoding)
        precondition(expansion.missingArguments.isEmpty)
        precondition(expansion.text == "https://example.com/?q=caf%C3%A9%20%26%20a%2Fb%3F")
        precondition(
            QuicklinkDestination.detect(expansion.text, homeDirectory: home)
                == .web(URL(string: expansion.text)!))
        let fixed = SnippetTemplateEngine.expand(
            text: "https://example.com/a%20b", context: context,
            userArguments: ["Argument": "ignored"], encoding: .percentEncoding)
        precondition(fixed.text == "https://example.com/a%20b")
        precondition(QuicklinkDestination.detect("example.com", homeDirectory: home)
            == .web(URL(string: "https://example.com")!))
        precondition(QuicklinkDestination.detect("~/Notes", homeDirectory: home) == .path(home + "/Notes"))
        print("Verified launcher-quicklinks: query alias, missing arguments, Unicode escaping and fixed URLs")
    }

    private static func expectError(_ expected: QuicklinkError, _ body: () throws -> Void) {
        do {
            try body()
            preconditionFailure("Expected \(expected)")
        } catch let failure as QuicklinkError {
            precondition(failure == expected)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
