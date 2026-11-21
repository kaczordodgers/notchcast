// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/ArchivesAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesEnvironment.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveCompressor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveProcess.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

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

/// Plays ditto, 7-Zip and bsdtar: each writes a stand-in archive where it is told to.
final class FakeCompressors: Sendable {
    struct State {
        var calls: [[String]] = []
        var installed: Set<String> = ["ditto", "7zz", "7z", "bsdtar", "zstd"]
        var status: Int32 = 0
        var hold = false
        var held: CheckedContinuation<Bool, Never>?
        var heldStarted = false
        /// Written while the tool runs, as another app would.
        var appears: [URL] = []
        var staged: [URL] = []
        var cloned: [String] = []
        /// Each clone that is a link, by name, with where it points.
        var clonedLinks: [String: String] = [:]
    }

    let state = Mutex(State())

    func locate(_ name: String) -> URL? {
        state.withLock { $0.installed.contains(name) } ? URL(filePath: "/fake/bin/\(name)") : nil
    }

    /// Lets a held tool finish its archive.
    func release() { state.withLock { $0.held?.resume(returning: true) } }

    func run(_ tool: URL, _ arguments: [String]) async throws -> ArchiveProcessResult {
        try Task.checkCancellation()
        let name = tool.lastPathComponent
        let path = switch name {
        case "ditto": arguments.last!
        case "bsdtar": arguments[arguments.firstIndex(of: "-cf")! + 1]
        default: arguments[arguments.firstIndex(of: "--")! + 1]
        }
        let staged = URL(filePath: path)
        let items = URL(filePath: arguments[arguments.count - 2])
        let cloned = name == "ditto" && items.lastPathComponent == "Items"
            ? ((try? FileManager.default.contentsOfDirectory(atPath: items.path)) ?? []).sorted() : []
        let links = cloned.reduce(into: [String: String]()) { links, name in
            links[name] = try? FileManager.default.destinationOfSymbolicLink(atPath: items.appending(path: name).path)
        }
        let (appears, hold, status) = state.withLock { state in
            state.calls.append([name] + arguments)
            state.staged.append(staged)
            state.cloned = cloned
            state.clonedLinks = links
            return (state.appears, state.hold, state.status)
        }
        for url in appears { try Data("newcomer".utf8).write(to: url) }
        if hold {
            let released = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    state.withLock {
                        $0.heldStarted = true
                        $0.held = continuation
                    }
                }
            } onCancel: {
                state.withLock { $0.held?.resume(returning: false) }
            }
            guard released else { throw CancellationError() }
        }
        guard status == 0 else { return ArchiveProcessResult(status: status, errors: "Scanning\nERROR: disk full\n") }
        try Data("archive".utf8).write(to: staged)
        return ArchiveProcessResult(status: 0)
    }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [(notice: IslandNotice, onTap: (@MainActor () -> Void)?)] = []
    var ends: [String] = []

    var texts: [String] { posts.map(\.notice.text) }
    var failures: [String] { posts.filter(\.notice.isFailure).map(\.notice.text) }

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append((notice, onTap)) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// What the fake Mac was asked, and the Finder selection it answers with.
@MainActor
final class Record {
    var questions: [String] = []
    var answer = true
    /// Keeps the next question open until the test answers it through `held`.
    var hold = false
    var held: CheckedContinuation<Bool, Never>?
    var reveals: [URL] = []
    var selection: [URL] = []
    var selectionFailure: ArchiveFailure?
}

@MainActor
final class Rig {
    let suite = "nc-Archives-compress-test.\(UUID())"
    let root: URL
    /// The folder Finder shows: `a.txt` and `b.txt`, selected.
    let folder: URL
    let presenter = FakePresenter()
    let tools = FakeCompressors()
    let record = Record()
    let controller: NotchcastController

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-compress-\(UUID())", directoryHint: .isDirectory)
        let folder = root.appending(path: "Trip", directoryHint: .isDirectory)
        (self.root, self.folder) = (root, folder)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "archives")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt"] { try Data("input \(name)".utf8).write(to: folder.appending(path: name)) }
        record.selection = [folder.appending(path: "a.txt"), folder.appending(path: "b.txt")]
        let (tools, record) = (tools, record)
        let unused = ArchiveExtractor(locate: { _ in nil }, run: { _, _, _ in ArchiveProcessResult(status: 1) })
        harnessEnvironment = ArchivesEnvironment(
            journal: root.appending(path: "support/archives.json"),
            extractor: unused,
            compressor: ArchiveCompressor(locate: { tools.locate($0) }, run: { try await tools.run($0, $1) }),
            finderSelection: {
                if let failure = record.selectionFailure { throw failure }
                return record.selection
            },
            setDefaultApp: { _ in },
            reveal: { record.reveals.append($0) },
            pickArchives: { [] })
        let hub = NotchcastTapHub(
            syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in fatalError("Archives installs no tap") })
        controller = NotchcastController(
            addons: [ArchivesAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(), presenter: presenter)
        controller.context(forSwitch: "archives")?.confirm = { title, message, _ in
            record.questions.append(title + "\n" + (message ?? ""))
            guard record.hold else { return record.answer }
            return await withCheckedContinuation { record.held = $0 }
        }
        controller.start()
    }

    var module: ArchivesModule? { controller.context(forSwitch: "archives")?.module(ArchivesModule.self) }

    func compress(_ format: ArchiveFormat) async {
        module!.compress(format)
        await module!.drainCompression()
    }

    var visible: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    func bytes(_ name: String) -> String {
        (try? Data(contentsOf: folder.appending(path: name))).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    var calls: [[String]] { tools.state.withLock { $0.calls } }

    /// Every private folder a tool wrote in is gone.
    var leftovers: [URL] {
        tools.state.withLock { $0.staged }.map { $0.deletingLastPathComponent() }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func waitForHeldTool() async {
        while !tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    }

    func finish() {
        controller.stop()
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
func eachFormat() async throws {
    let tools = [ArchiveFormat.zip: "ditto", .sevenZip: "7zz", .tarZstd: "bsdtar"]
    for format in ArchiveFormat.allCases {
        let rig = try Rig()
        defer { rig.finish() }
        let name = "Trip.\(format.rawValue)"
        await rig.compress(format)
        check(rig.visible == ["Trip.\(format.rawValue)", "a.txt", "b.txt"].sorted(),
              "\(format): a two-file selection gives exactly one new file beside it: \(rig.visible)")
        check(rig.bytes("a.txt") == "input a.txt" && rig.bytes("b.txt") == "input b.txt", "\(format): inputs unchanged")
        check(rig.bytes(name) == "archive", "\(format): the tool's archive is what was published")
        check(rig.calls.map(\.[0]) == [tools[format]!], "\(format): one program call: \(rig.calls)")
        check(rig.presenter.texts == ["Compressing \(name)", "Compressed \(name)"], "\(format): \(rig.presenter.texts)")
        check(rig.presenter.posts[0].notice.progress != nil, "\(format): the running compression shows progress")
        check(rig.presenter.ends == ["archives.compressing"], "\(format): the progress notice ends: \(rig.presenter.ends)")
        rig.presenter.posts[1].onTap?()
        check(rig.record.reveals.map(\.lastPathComponent) == [name], "\(format): a tap reveals the archive")
        check(rig.leftovers.isEmpty, "\(format): no private folder is left: \(rig.leftovers)")
        if format == .zip {
            check(rig.tools.state.withLock { $0.cloned } == ["a.txt", "b.txt"], "several items reach ditto as clones")
        }
    }
}

@MainActor
func oneItem() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.record.selection = [rig.folder.appending(path: "a.txt")]
    await rig.compress(.zip)
    check(rig.visible == ["a.txt", "a.txt.zip", "b.txt"], "one file keeps its whole name: \(rig.visible)")
    check(rig.calls[0].contains(rig.folder.appending(path: "a.txt").path), "a lone file goes to ditto as itself")
}

@MainActor
func loneLink() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let link = rig.folder.appending(path: "link")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "a.txt")
    rig.record.selection = [link]
    await rig.compress(.zip)
    let work = rig.tools.state.withLock { $0.staged }[0].deletingLastPathComponent()
    check(rig.calls == [[
        "ditto", "-c", "-k", "--sequesterRsrc", work.appending(path: "Items").path, work.appending(path: "Output.zip").path,
    ]], "a lone link goes to ditto inside the clones' folder: \(rig.calls)")
    check(rig.tools.state.withLock { $0.clonedLinks } == ["link": "a.txt"], "and ditto meets it still as a link")
    check(rig.visible == ["a.txt", "b.txt", "link", "link.zip"], "\(rig.visible)")
}

@MainActor
func neverOverwrites() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    try Data("old".utf8).write(to: rig.folder.appending(path: "Trip.zip"))
    await rig.compress(.zip)
    check(rig.bytes("Trip.zip") == "old" && rig.bytes("Trip 2.zip") == "archive", "an existing name keeps its bytes")
    check(rig.presenter.texts.last == "Compressed Trip 2.zip", "\(rig.presenter.texts)")

    rig.tools.state.withLock { $0.appears = [rig.folder.appending(path: "Trip 3.zip")] }
    await rig.compress(.zip)
    check(rig.bytes("Trip 3.zip") == "newcomer" && rig.bytes("Trip 4.zip") == "archive",
          "a name taken while the tool ran goes to the next number, the newcomer intact: \(rig.visible)")
}

@MainActor
func toolFailure() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.status = 2 }
    await rig.compress(.sevenZip)
    check(rig.presenter.failures == ["ERROR: disk full"], "one notice with the tool's last line: \(rig.presenter.failures)")
    check(rig.visible == ["a.txt", "b.txt"], "no new file: \(rig.visible)")
    check(rig.leftovers.isEmpty, "no private folder: \(rig.leftovers)")
}

@MainActor
func refusesBeforeAnyTool() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    func refused(_ expected: String) async {
        await rig.compress(.zip)
        check(rig.presenter.failures.last == expected, "\(expected), got \(rig.presenter.failures)")
    }
    rig.record.selection = []
    await refused("Select files or folders in Finder first.")
    rig.record.selectionFailure = .automationRefused
    await refused("Allow Automation access to read the Finder selection.")
    rig.record.selectionFailure = nil
    rig.record.selection = [rig.folder.appending(path: "a.txt"), rig.root.appending(path: "c.txt")]
    await refused("Select items from one folder.")
    rig.record.selection = [URL(filePath: "/", directoryHint: .isDirectory)]
    await refused("/ cannot be compressed.")
    let pipe = rig.folder.appending(path: "pipe")
    check(mkfifo(pipe.path, 0o600) == 0, "made the fixture pipe")
    rig.record.selection = [rig.folder.appending(path: "a.txt"), pipe]
    await refused("pipe cannot be compressed.")
    try FileManager.default.removeItem(at: pipe)
    rig.record.selection = [rig.folder.appending(path: "a.txt")]
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rig.folder.path)
    await refused("Notchcast cannot write to Trip.")
    check(rig.calls.isEmpty, "no tool ran: \(rig.calls)")
    check(!rig.presenter.texts.contains { $0.hasPrefix("Compressing") }, "no progress for a refusal: \(rig.presenter.texts)")
}

@MainActor
func missingTools() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.installed = ["ditto", "bsdtar"] }
    await rig.compress(.sevenZip)
    await rig.compress(.tarZstd)
    check(rig.presenter.failures == [
        "7zz is not installed. Install it with: brew install sevenzip",
        "zstd is not installed. Install it with: brew install zstd",
    ], "each missing tool is named with its install line: \(rig.presenter.failures)")
    check(rig.calls.isEmpty, "nothing ran: \(rig.calls)")
    await rig.compress(.zip)
    check(rig.calls.map(\.[0]) == ["ditto"], "ZIP needs nothing beyond macOS: \(rig.calls)")
    rig.tools.state.withLock { $0.installed = ["7z"] }
    await rig.compress(.sevenZip)
    check(rig.calls.map(\.[0]) == ["ditto", "7z"], "p7zip's 7z stands in for 7zz: \(rig.calls)")
}

@MainActor
func stopMidRun() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.hold = true }
    rig.module!.compress(.zip)
    await rig.waitForHeldTool()
    rig.record.answer = false
    rig.presenter.posts[0].onTap?()
    while rig.record.questions.isEmpty { await Task.yield() }
    for _ in 0..<5 { await Task.yield() }
    check(rig.record.questions[0] == "Stop compressing Trip.zip?\nNothing is kept. The selected files stay as they are.",
          rig.record.questions[0])
    check(rig.module!.compression?.task.isCancelled == false, "a no keeps it running")
    rig.record.answer = true
    rig.presenter.posts[0].onTap?()
    await rig.module!.drainCompression()
    check(rig.presenter.texts == ["Compressing Trip.zip", "Stopped compressing Trip.zip"], "\(rig.presenter.texts)")
    check(rig.visible == ["a.txt", "b.txt"] && rig.leftovers.isEmpty, "nothing is left: \(rig.visible) \(rig.leftovers)")
}

@MainActor
func lateYes() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.hold = true }
    rig.record.hold = true
    rig.module!.compress(.zip)
    await rig.waitForHeldTool()
    rig.presenter.posts[0].onTap?()
    while rig.record.held == nil { await Task.yield() }
    rig.tools.release()
    await rig.module!.drainCompression()
    rig.tools.state.withLock { ($0.held, $0.heldStarted) = (nil, false) }
    rig.module!.compress(.sevenZip)
    await rig.waitForHeldTool()
    rig.record.held!.resume(returning: true)
    for _ in 0..<5 { await Task.yield() }
    check(rig.module!.compression?.task.isCancelled == false, "a yes after its job ended leaves the next one running")
    rig.tools.release()
    await rig.module!.drainCompression()
    check(rig.presenter.texts == ["Compressing Trip.zip", "Compressed Trip.zip", "Compressing Trip.7z", "Compressed Trip.7z"],
          "\(rig.presenter.texts)")
    check(rig.visible == ["Trip.7z", "Trip.zip", "a.txt", "b.txt"], "both archives are kept: \(rig.visible)")
}

/// exFAT and SMB answer RENAME_EXCL with ENOTSUP; publishing then moves without overwriting.
@MainActor
func noExclusiveRename() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let plan = try ArchiveCompression.plan(
        format: .zip, selection: rig.record.selection, kind: ArchiveCompressor.kind,
        isWritable: ArchiveCompressor.isWritable)
    func staged() throws -> URL {
        let url = rig.root.appending(path: "staged-\(UUID()).zip")
        try Data("archive".utf8).write(to: url)
        return url
    }
    var tried: [String] = []
    let made = try ArchiveCompressor.publish(try staged(), plan: plan) { _, target in
        tried.append(target.lastPathComponent)
        if tried.count == 1 { try? Data("newcomer".utf8).write(to: target) }
        return ENOTSUP
    }
    check(tried == ["Trip.zip", "Trip 2.zip"] && made.lastPathComponent == "Trip 2.zip", "\(tried) \(made)")
    check(rig.bytes("Trip.zip") == "newcomer" && rig.bytes("Trip 2.zip") == "archive",
          "a name taken before the move keeps its bytes; the archive takes the next: \(rig.visible)")
    let second = try ArchiveCompressor.publish(try staged(), plan: plan) { _, _ in EINVAL }
    check(second.lastPathComponent == "Trip 3.zip" && rig.bytes("Trip 3.zip") == "archive", "EINVAL moves too")
    let kept = try staged()
    do {
        _ = try ArchiveCompressor.publish(kept, plan: plan) { _, _ in EIO }
        check(false, "another error is reported")
    } catch ArchiveFailure.compressionFailed(let detail) {
        check(detail == String(cString: strerror(EIO)), detail)
    }
    check(rig.visible == ["Trip 2.zip", "Trip 3.zip", "Trip.zip", "a.txt", "b.txt"], "nothing else moved: \(rig.visible)")
}

@MainActor
func oneAtATime() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.hold = true }
    rig.module!.compress(.zip)
    await rig.waitForHeldTool()
    rig.module!.compress(.sevenZip)
    check(rig.presenter.failures == ["Wait for Trip.zip to finish."], "\(rig.presenter.failures)")
    rig.tools.release()
    await rig.module!.drainCompression()
    check(rig.visible == ["Trip.zip", "a.txt", "b.txt"], "the first one finishes: \(rig.visible)")
    check(rig.calls.count == 1, "the second never ran: \(rig.calls)")
}

@MainActor
func switchedOff() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.hold = true }
    rig.module!.compress(.tarZstd)
    await rig.waitForHeldTool()
    let task = rig.module!.compression!.task
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    await task.value
    check(rig.visible == ["a.txt", "b.txt"] && rig.leftovers.isEmpty, "nothing is left: \(rig.visible) \(rig.leftovers)")
    check(rig.presenter.ends.contains("archives.compressing"), "the progress notice goes with the module")
    check(rig.presenter.texts == ["Compressing Trip.tar.zst"], "a switch-off posts nothing more: \(rig.presenter.texts)")
}

@main
enum ArchivesCompressTest {
    @MainActor
    static func main() async throws {
        try await eachFormat()
        try await oneItem()
        try await loneLink()
        try await neverOverwrites()
        try await noExclusiveRename()
        try await toolFailure()
        try await refusesBeforeAnyTool()
        try await missingTools()
        try await stopMidRun()
        try await lateYes()
        try await oneAtATime()
        try await switchedOff()
        print("nc-Archives-compress-test: ok")
    }
}
