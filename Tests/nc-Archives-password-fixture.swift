import AppKit
import Synchronization
import SwiftUI

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ArchivesSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

@MainActor var harnessEnvironment: ArchivesEnvironment?

extension ArchivesEnvironment {
    static func live() -> Self { harnessEnvironment! }
}

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fatalError(message()) }
}

/// Every password the harness types carries this, so a leak anywhere is one `contains` away.
let marker = "7Qx"
let (right, wrong) = ("nc-right-7Qx", "nc-wrong-7Qx")
let variable = "HATCHZIP_PASSWORD"
let twoFiles = """
          Size  Name
           1 B  a.txt
           1 B  b/c.txt
    2 entries, 2 B uncompressed, 7 B zip archive
    """

final class FakeTools: Sendable {
    struct Call {
        var tool: String
        var arguments: [String]
        var environment: [String: String]
    }

    struct State {
        var calls: [Call] = []
        var passwords: [String: String] = [:]
        var hiddenNames: Set<String> = []
        var extractStatuses: [Int32] = []
        var extractOnlyPasswords: Set<String> = []
        var hold: Set<String> = []
        var held: CheckedContinuation<Void, Never>?
        var heldStarted = false
        var journalInPlaceAtExtract: [Bool] = []
        var journalLeaks = 0
    }

    let state = Mutex(State())
    let journal: URL

    init(journal: URL) { self.journal = journal }

    static func writeJournal(archive: URL, output: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "parts": [[archive.path, ArchiveExtractor.size(archive) ?? 0]], "output": output.path,
        ], options: .sortedKeys)
        try data.write(to: URL(filePath: archive.path + ".hatchzip"))
    }

    func locate(_ name: String) -> URL? { URL(filePath: "/fake/bin/\(name)") }

    func run(_ tool: URL, _ arguments: [String], _ environment: [String: String]) async throws -> ArchiveProcessResult {
        try Task.checkCancellation()
        let name = tool.lastPathComponent
        let journalled = (try? Data(contentsOf: journal)) ?? Data()
        state.withLock {
            $0.calls.append(Call(tool: name, arguments: arguments, environment: environment))
            if journalled.range(of: Data(marker.utf8)) != nil { $0.journalLeaks += 1 }
        }
        let archive = URL(filePath: arguments[1])
        if name == "bsdtar" {
            guard arguments[0] == "-tvf" else { return try extract(into: URL(filePath: arguments.last!)) }
            return ArchiveProcessResult(status: 0, output: "-rw-r--r--  0 me  staff  1 Jan  1 12:00 a.txt\n")
        }
        let side = archive.path + ".hatchzip"
        let journal = (try? Data(contentsOf: URL(filePath: side)))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        if let journal,
            (journal["parts"] as? [[Any]])?.first?.first as? String != archive.path
        {
            return ArchiveProcessResult(status: 1, errors: "error: \(side) does not belong to \(archive.path)")
        }
        let password = state.withLock { state -> String? in
            if arguments[0] == "list", state.extractOnlyPasswords.contains(archive.lastPathComponent) { return nil }
            return state.passwords[archive.lastPathComponent]
        }
        if let password, ["list", "extract", "check"].contains(arguments[0]), environment[variable] != password {
            return ArchiveProcessResult(status: 5, errors: "Incorrect password.\nerror: incorrect password\n")
        }
        switch arguments[0] {
        case "list": return ArchiveProcessResult(status: 0, output: twoFiles)
        case "check": return ArchiveProcessResult(status: 0, output: "required 29.9 MB")
        case "restore":
            guard FileManager.default.fileExists(atPath: side) else { return ArchiveProcessResult(status: 1) }
            if state.withLock({ $0.hiddenNames.contains(archive.lastPathComponent) }) {
                return ArchiveProcessResult(status: 1, errors: "error: has encrypted file names")
            }
            try FileManager.default.removeItem(atPath: side)
            return ArchiveProcessResult(status: 0)
        default: break
        }
        let output = URL(filePath: arguments[arguments.firstIndex(of: "-o")! + 1])
        if let started = journal?["output"] as? String, started != output.path {
            let detail = "this archive is already partially extracted to \(started)"
            return ArchiveProcessResult(status: 1, errors: "error: \(detail). Complete or restore that extraction first")
        }
        let jobs = ArchiveJob.decode(journalled)
        state.withLock { $0.journalInPlaceAtExtract.append(jobs.first { $0.archive == archive }?.inPlace ?? false) }
        if state.withLock({ $0.hold.contains(archive.lastPathComponent) }) {
            try Self.writeJournal(archive: archive, output: output)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data("half".utf8).write(to: output.appending(path: "a.txt"))
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    state.withLock {
                        $0.heldStarted = true
                        $0.held = continuation
                    }
                }
            } onCancel: {
                state.withLock { $0.held?.resume() }
            }
            throw CancellationError()
        }
        let status = state.withLock { $0.extractStatuses.isEmpty ? 0 : $0.extractStatuses.removeFirst() }
        guard status == 0 else { return ArchiveProcessResult(status: status, errors: "error: no room") }
        try? FileManager.default.removeItem(atPath: side)
        return try extract(into: output)
    }

    private func extract(into output: URL) throws -> ArchiveProcessResult {
        for file in ["a.txt", "b/c.txt"] {
            let url = output.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        return ArchiveProcessResult(status: 0)
    }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var texts: [String] { posts.map(\.text) }
    var failures: [String] { posts.filter(\.isFailure).map(\.text) }

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// The password dialog as the core hook answers it: one queued answer per question, nil for Cancel.
@MainActor
final class Record {
    struct Ask: Equatable {
        var title: String
        var message: String?
        var field: String
        var confirm: String
    }

    var asks: [Ask] = []
    var answers: [String?] = []
    var besideAtAsk: [[String]] = []
    var holdAsk = false
    var heldAsk: CheckedContinuation<Void, Never>?
    var confirms: [String] = []
    var inPlaceAnswer = true
}

@MainActor
final class Rig {
    let suite = "nc-Archives-password-test.\(UUID())"
    let defaults: UserDefaults
    let folder: URL
    let presenter = FakePresenter()
    let tools: FakeTools
    let record = Record()
    let controller: NotchcastController

    static let testDate = Date(timeIntervalSinceReferenceDate: 900_000_000)

    init(
        folder existing: URL? = nil, hook: Bool = true, answers: [String?] = [], journal: [ArchiveJob] = [],
        passwords: [String: String] = [:], hiddenNames: Set<String> = [], now: Date = Rig.testDate,
        extractor: ArchiveExtractor? = nil
    ) throws {
        folder = existing ?? FileManager.default.temporaryDirectory.appending(
            path: "nc-archives-pw-\(UUID())", directoryHint: .isDirectory)
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "archives")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journalURL = folder.appending(path: "support/archives.json")
        tools = FakeTools(journal: journalURL)
        tools.state.withLock {
            $0.passwords = passwords
            $0.hiddenNames = hiddenNames
        }
        if !journal.isEmpty {
            try FileManager.default.createDirectory(
                at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ArchiveJob.encode(journal).write(to: journalURL)
        }
        let (tools, record, folder) = (tools, record, folder)
        record.answers = answers
        harnessEnvironment = ArchivesEnvironment(
            journal: journalURL,
            extractor: extractor ?? ArchiveExtractor(
                locate: { tools.locate($0) }, run: { try await tools.run($0, $1, $2) }),
            compressor: ArchiveCompressor(locate: { _ in nil }, run: { _, _ in ArchiveProcessResult(status: 1) }),
            finderSelection: { [] }, setDefaultApp: { _ in }, reveal: { _ in }, pickArchives: { [] })
        let hub = NotchcastTapHub(
            syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in fatalError("Archives installs no tap") })
        controller = NotchcastController(
            addons: [ArchivesAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { now })
        let context = controller.context(forSwitch: "archives")!
        context.confirm = { title, _, _ in
            record.confirms.append(title)
            return record.inPlaceAnswer
        }
        if hook {
            context.askSecret = { title, message, field, confirm in
                record.asks.append(Record.Ask(title: title, message: message, field: field, confirm: confirm))
                record.besideAtAsk.append(
                    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != "support" }
                        .sorted())
                if record.holdAsk { await withCheckedContinuation { record.heldAsk = $0 } }
                return record.answers.isEmpty ? nil : record.answers.removeFirst()
            }
        }
        controller.start()
    }

    var module: ArchivesModule? { controller.context(forSwitch: "archives")?.module(ArchivesModule.self) }
    var calls: [FakeTools.Call] { tools.state.withLock { $0.calls } }
    var steps: [String] { calls.map { $0.arguments[0] } }

    @discardableResult
    func archive(_ name: String) -> URL {
        let url = folder.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data("archive \(name)".utf8))
        }
        return url
    }

    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: folder.appending(path: name).path) }
    func bytes(_ name: String) -> Data? { try? Data(contentsOf: archive(name)) }

    var visible: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != "support" }.sorted()
    }

    var staging: [String] { visible.filter { $0.hasPrefix(".notchcast-extract-") } }

    func journal() -> [ArchiveJob] {
        ArchiveJob.decode((try? Data(contentsOf: harnessEnvironment!.journal)) ?? Data())
    }

    func extract(_ names: String...) async {
        module!.open(names.map { archive($0) })
        await module!.drain()
    }

    func audit() {
        for call in calls {
            check(!call.arguments.contains { $0.contains(marker) }, "a password reached arguments: \(call.arguments)")
            check(call.environment.keys.allSatisfy { $0 == variable }, "only the variable is added: \(call.environment)")
            if call.environment[variable] != nil {
                check(call.tool == "hatchzip" && ["list", "extract", "check"].contains(call.arguments[0]),
                      "only HatchZip's list, extract and check get it: \(call.tool) \(call.arguments)")
            }
        }
        check(tools.state.withLock { $0.journalLeaks } == 0, "the journal never holds a password")
        let saved = (try? Data(contentsOf: harnessEnvironment!.journal)) ?? Data()
        check(saved.range(of: Data(marker.utf8)) == nil, "the journal never holds a password")
        check(!presenter.texts.contains { $0.contains(marker) }, "no notice holds a password: \(presenter.texts)")
    }

    func finish(keepingFolder: Bool = false) {
        audit()
        controller.stop()
        if !keepingFolder { try? FileManager.default.removeItem(at: folder) }
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
