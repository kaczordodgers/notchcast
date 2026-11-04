// notchcast-sources: Tinycast/Features/DocumentEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/Service/*.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteDocument.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteEditAction.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteEditPlan.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteFormatting.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdown.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdownEditing.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdownParser.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteInlineScanner.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteTitle.swift
import Darwin
import Foundation

@main
@MainActor
struct EditorDocumentTests {
    private static func check(
        _ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) rethrows {
        let passed = try value()
        precondition(passed, file: file, line: line)
    }

    static func main() async throws {
        try codec()
        try await repository()
        try await recovery()
        try await sessions()
        try await statistics()
        preferences()
        print("Document editor: byte fidelity, conflicts, deletion, autosave, Markdown and text policies passed")
    }

    private static func codec() throws {
        let sources = ["", "a\r\nb\rc\n", "no newline", "\0", "e\u{301} 👨‍👩‍👧‍👦\t", "\u{FEFF}body"]
        let formats: [(String.Encoding, Data)] = [
            (.utf8, Data()), (.utf8, Data([0xEF, 0xBB, 0xBF])),
            (.utf16LittleEndian, Data([0xFF, 0xFE])), (.utf16BigEndian, Data([0xFE, 0xFF]))
        ]
        for source in sources {
            for (encoding, mark) in formats {
                let bytes = mark + source.data(using: encoding)!
                let snapshot = try EditorDocumentSnapshot(bytes: bytes)
                try check(try snapshot.encoded(snapshot.source) == bytes)
                try check(try snapshot.encoded(snapshot.source + "x") == bytes + "x".data(using: encoding)!)
            }
        }
        let legacy = "Zażółć gęślą jaźń".data(using: .windowsCP1250)!
        let snapshot = try EditorDocumentSnapshot(bytes: legacy)
        precondition(snapshot.encoding == .windowsCP1250)
        try check(try snapshot.encoded(snapshot.source) == legacy)
        do {
            _ = try snapshot.encoded("🙂")
            preconditionFailure("unrepresentable characters must fail")
        } catch EditorFailure.invalidEncoding {}
        let decomposed = try EditorDocumentSnapshot(bytes: Data("e\u{301}".utf8))
        try check(try decomposed.encoded("é") == Data("é".utf8))
    }

    private static func repository() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("any.md")
        let bytes = Data("# Heading\r\nbody\rno newline\0".utf8)
        try bytes.write(to: url)
        let original = try await EditorDocumentRepository.load(url)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileResourceIdentifierKey])
        _ = try await EditorDocumentRepository.save(original.source, to: url, expecting: original)
        try check(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            == values.contentModificationDate)
        try Data("external".utf8).write(to: url, options: .atomic)
        do {
            _ = try await EditorDocumentRepository.save("mine", to: url, expecting: original)
            preconditionFailure("must detect external change")
        } catch EditorFailure.externalChange {}
        try check(try Data(contentsOf: url) == Data("external".utf8))
        let attribute = "com.notchcast.editor-test"
        let tag = Data("finder metadata".utf8)
        let result = tag.withUnsafeBytes { buffer in
            setxattr(url.path, attribute, buffer.baseAddress, buffer.count, 0, 0)
        }
        precondition(result == 0)
        let beforeReplacement = try await EditorDocumentRepository.load(url)
        _ = try await EditorDocumentRepository.save("replacement", to: url, expecting: beforeReplacement)
        var actual = Data(count: tag.count)
        let count = actual.withUnsafeMutableBytes { buffer in
            getxattr(url.path, attribute, buffer.baseAddress, buffer.count, 0, 0)
        }
        precondition(count == tag.count && actual == tag)
        let hardLink = directory.appendingPathComponent("linked.md")
        try FileManager.default.linkItem(at: url, to: hardLink)
        let beforeLinkedSave = try await EditorDocumentRepository.load(url)
        _ = try await EditorDocumentRepository.save("linked replacement", to: url, expecting: beforeLinkedSave)
        try check(try Data(contentsOf: hardLink) == Data("linked replacement".utf8))
        let restored = try await EditorDocumentRepository.load(url)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await EditorDocumentRepository.save("mine", to: url, expecting: restored)
            preconditionFailure("must not recreate a deleted file")
        } catch EditorFailure.missingFile {}
        let copy = directory.appendingPathComponent("saved.txt")
        _ = try await EditorDocumentRepository.create(original.source, at: copy, format: original)
        try check(try Data(contentsOf: copy) == bytes)
        do {
            _ = try await EditorDocumentRepository.create("replace", at: copy, format: original)
            preconditionFailure("Save As must not silently overwrite")
        } catch {}
        try check(try Data(contentsOf: copy) == bytes)
        do {
            _ = try EditorDocumentRepository.kind(of: directory.appendingPathComponent("rich.rtf"))
            preconditionFailure("rich text is unsupported")
        } catch EditorFailure.unsupportedFile {}
    }

    private static func recovery() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = EditorDocumentSession(
            url: directory.appendingPathComponent("legacy.txt"),
            snapshot: try EditorDocumentSnapshot(bytes: Data()), rendersMarkdown: false)
        document.setEnabled(true)
        defer { document.setEnabled(false) }
        precondition(document.edit("unsaved 🙂\r\ntext"))
        let recovered = try await EditorRecoveryService.flush(document, directory: directory) {
            throw EditorFailure.invalidEncoding
        }
        precondition(recovered != nil)
        try check(try Data(contentsOf: recovered!) == Data(document.source.utf8))
        precondition(document.isDirty)
    }

    private static func sessions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("note.md")
        try Data("original".utf8).write(to: url)
        let document = EditorDocumentSession(
            url: url, snapshot: try await EditorDocumentRepository.load(url), rendersMarkdown: true)
        document.setEnabled(true)
        defer { document.setEnabled(false) }
        precondition(document.edit("mine"))
        try Data("external".utf8).write(to: url, options: .atomic)
        try await document.refresh()
        precondition(document.source == "mine" && document.externalVersion?.source == "external")
        do {
            try await document.save()
            preconditionFailure("autosave must not overwrite a conflict")
        } catch EditorFailure.externalChange {}
        try await document.saveMyChanges()
        try check(try Data(contentsOf: url) == Data("mine".utf8))
        precondition(!document.isDirty)
        precondition(document.edit("draft"))
        try Data("external 2".utf8).write(to: url, options: .atomic)
        try await document.refresh()
        try document.reloadExternalVersion()
        precondition(document.source == "external 2" && !document.isDirty)
        precondition(document.edit("# Heading\n- [ ] task"))
        let plan = document.plan(.toggleTask(lineIndex: 1), selection: NSRange(location: 0, length: 0))
        precondition(plan?.replacement.contains("x") == true)
        try await document.flush()
        try check(try Data(contentsOf: url) == Data(document.source.utf8))
        precondition(document.edit("unsaved"))
        try FileManager.default.removeItem(at: url)
        do {
            try await document.refresh()
            preconditionFailure("deletion must be visible")
        } catch EditorFailure.missingFile {}
        precondition(document.source == "unsaved" && document.isDirty)
        let copy = directory.appendingPathComponent("new.txt")
        try await document.saveAs(copy)
        precondition(document.url == copy && !document.rendersMarkdown && !document.isDirty)
        precondition(document.plan(.toggleInline(.bold), selection: NSRange(location: 0, length: 0)) == nil)
        document.brainDump = true
        precondition(!document.edit("short"))
        precondition(document.edit("unsaved longer"))
        try await document.flush()
        document.setEnabled(false)
        precondition(!document.edit("disabled"))
        document.setEnabled(true)
        precondition(document.edit("autosaved after restart"))
        while document.isDirty {
            try await Task.sleep(for: .milliseconds(50))
        }
        try check(try Data(contentsOf: copy) == Data("autosaved after restart".utf8))
        precondition(!document.isDirty)
        for external in ["first external replacement", "second external replacement"] {
            try Data(external.utf8).write(to: copy, options: .atomic)
            while document.source != external {
                try await Task.sleep(for: .milliseconds(50))
            }
            precondition(document.source == external && !document.isDirty)
        }
    }

    private static func statistics() async throws {
        let counts = await EditorStatistics.count("One 👨‍👩‍👧‍👦\r\ne\u{301}\r\n")
        precondition(counts.words == 3 && counts.characters == 6 && counts.lines == 3)
        precondition(EditorTextPolicy.lineCount("") == 1)
        precondition(EditorTextPolicy.horizontalInset(width: 1000, pointSize: 15, columnCharacters: 64, glyphWidth: 8) == 244)
        precondition(EditorTextPolicy.horizontalInset(width: 100, pointSize: 15, columnCharacters: 64, glyphWidth: 8) == 35)
        precondition(!EditorTextPolicy.accepts("same", after: "size", brainDump: true))
        precondition(EditorTextPolicy.accepts("text", after: "text\n", brainDump: true))
        precondition(!EditorTextPolicy.accepts("text", after: " text", brainDump: true))
        let base = URL(fileURLWithPath: "/tmp/editor/folder/file.md")
        precondition(EditorTextPolicy.relativeMarkdownLink("../other.md", from: base)?.path == "/tmp/editor/other.md")
        precondition(EditorTextPolicy.relativeMarkdownLink("https://example.com/file.md", from: base) == nil)
    }

    private static func preferences() {
        let suite = "app.notchcast.test.editor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        precondition(preferences.font == .jetBrainsMono && preferences.theme == .githubDark)
        preferences.font = .system
        preferences.theme = .system
        preferences.pairsAutomatically = false
        let restored = EditorPreferences(defaults: defaults)
        precondition(restored.font == .system && restored.theme == .system && !restored.pairsAutomatically)
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("editor-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
