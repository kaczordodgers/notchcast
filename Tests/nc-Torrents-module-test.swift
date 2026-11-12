// notchcast-sources: Tinycast/Features/Torrents/Model/*.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentModule.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentAria2Session.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentManager.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentQueueHost.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentRPCClient.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentS*.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentTool*.swift
// notchcast-kit: platform core
// notchcast-sources: Tinycast/Features/NetMerge/Model/*.swift
// notchcast-sources: Tinycast/Features/NetMerge/Service/*.swift
// notchcast-sources: Tinycast/Features/Torrents/Settings/TorrentJob+Presentation.swift
import Foundation

// notchcast-sources: Tinycast/Features/Torrents/NotchcastTorrentModuleEntries.swift
// notchcast-sources: Tinycast/Features/Torrents/TorrentModule+Registration.swift
enum AppPaths {
    static func applicationSupport() -> URL { URL(fileURLWithPath: "/unused") }
}
@MainActor final class AppCore {
    var messages: [String] = []
    func showMessage(_ message: String) { messages.append(message) }
}

@main @MainActor
struct TorrentModuleTests {
    final class Session: TorrentSession {
        var isAlive: Bool { true }
        var arguments: [[String]] = []
        var sharing: [Bool] = []
        var finished = false
        var stops = 0
        var holdStop = false
        var stopped: CheckedContinuation<Void, Never>?

        func start(extraArguments: [String]) async throws { arguments.append(extraArguments) }
        func add(_ submission: TorrentSubmission, destination: URL, keepSharing: Bool) async throws -> String {
            sharing.append(keepSharing)
            return String(sharing.count)
        }
        func status(_ gid: String) async throws -> TorrentStatus {
            TorrentStatus(status: finished ? "complete" : "active", connections: "1")
        }
        func remove(_ gid: String) async throws {}
        func stop() async {
            stops += 1
            if holdStop {
                holdStop = false
                await withCheckedContinuation { stopped = $0 }
            }
        }
        func terminate() {}
    }

    struct MissingTool: TorrentToolLocating { func aria2c() -> URL? { nil } }

    static func until(_ message: String, _ predicate: () -> Bool) async throws {
        // A wedged wait fails by name instead of running into the suite's 300 s kill.
        let deadline = ContinuousClock.now + .seconds(60)
        while !predicate() {
            guard ContinuousClock.now < deadline else { fatalError("Timed out: \(message)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func main() async throws {
        try await processLifecycle()
        let suite = "torrent-module-test.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(preferences.isOn(.torrents) && preferences.isOn(.torrentsUseIPhone))
        precondition(!preferences.isOn(.torrentsKeepSharing))
        let session = Session()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TORRENT_TEST_ROOT"]
            ?? FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("module-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "test.TORRENT")
        try Data("d4:infod6:lengthi1e4:name1:xee".utf8).write(to: file)
        var reads = 0
        var phoneConnected = true
        var readFails = false
        let module = TorrentModule(
            session: session, preferences: preferences, destination: root, locator: MissingTool(),
            readInterfaces: {
                reads += 1
                if readFails { throw NetMergeInterfaceMonitor.Failure.dynamicStoreUnavailable }
                return [.init(bsdName: "en0", kind: .wifi, hasIPv4: true),
                        .init(bsdName: "en7", kind: .iPhoneUSB, hasIPv4: phoneConnected)]
            })
        let magnet = URL(string: "magnet:?xt=urn:btih:" + String(repeating: "a", count: 40))!
        precondition(!module.open(magnet))
        let controller = NotchcastModuleController(
            [.init(requires: [.torrents], module: module)], preferences: preferences)
        controller.run()
        precondition(module.isRunning && reads == 0 && session.arguments.isEmpty)
        preferences.set(.island, false)
        try await Task.sleep(for: .milliseconds(20))
        precondition(module.isRunning)
        for url in [URL(string: "https://example.invalid/a.torrent")!, root.appending(path: "a.zip")] {
            precondition(!module.open(url))
        }
        precondition(module.open(magnet))
        try await until("policy reaches aria2") { session.sharing.count == 1 }
        precondition(session.arguments == [["--multiple-interface=en0,en7"]])
        precondition(session.sharing == [false] && module.manager.jobs[0].usesIPhone && reads == 2)
        phoneConnected = false
        preferences.set(.torrentsKeepSharing, true)
        precondition(module.open(file))
        try await until("file routes to addTorrent") { session.sharing.count == 2 }
        precondition(session.sharing == [false, true] && session.arguments.count == 1 && reads == 3)
        precondition(!module.manager.jobs[1].usesIPhone)
        session.finished = true
        try await until("session idles") { module.manager.jobs.allSatisfy { $0.state == .finished } && session.stops > 0 }
        precondition(module.manager.jobs[0].usesIPhone)
        session.finished = false
        precondition(module.open(magnet))
        try await until("next session rereads interfaces") { session.sharing.count == 3 }
        precondition(reads == 4 && session.arguments.last == [] && !module.manager.jobs[2].usesIPhone)

        session.holdStop = true
        preferences.set(.torrents, false)
        precondition(!module.open(file))
        try await until("disabled module tears down") { session.stopped != nil }
        precondition(!module.isRunning && module.manager.jobs[2].state == .cancelled)
        module.tryAgain(module.manager.jobs[2].id)
        precondition(module.manager.jobs.count == 3)
        preferences.set(.torrents, true)
        try await until("re-enabled while stopping") { module.isRunning }
        preferences.set(.torrentsUseIPhone, false)
        precondition(module.open(file))
        precondition(module.manager.jobs.count == 3)
        session.stopped?.resume()
        session.stopped = nil
        try await until("buffered open survives shutdown") { session.sharing.count == 4 }
        precondition(reads == 4 && !module.manager.jobs[3].usesIPhone)
        preferences.set(.torrents, false)
        try await until("second stop") { !module.isRunning && module.manager.jobs[3].state == .cancelled }
        precondition(!module.open(magnet))
        await module.manager.stop()
        preferences.set(.torrentsUseIPhone, true)
        preferences.set(.torrents, true)
        try await until("third start") { module.isRunning }
        readFails = true
        precondition(module.open(magnet))
        try await until("read failure permits ordinary download") { session.sharing.count == 5 }
        precondition(session.arguments.last == [] && !module.manager.jobs[4].usesIPhone)
        precondition(!module.toolChecked)
        await module.refreshTool()
        precondition(module.toolURL == nil && module.toolChecked)
        var failed = TorrentJob(id: UUID(), source: magnet, destination: root, keepSharing: false)
        failed.state = .failed
        precondition(failed.displayName == String(localized: "Magnet link"))
        let named = URL(string: magnet.absoluteString + "&dn=Example")!
        failed = TorrentJob(id: UUID(), source: named, destination: root, keepSharing: false)
        failed.state = .failed
        precondition(failed.displayName == "Example")
        preferences.set(.torrents, false)
        try await until("final stop") { !module.isRunning }
        await module.manager.stop()
        precondition(!NotchcastPreferences(suiteName: suite).isOn(.torrents))
        precondition(NotchcastPreferences(suiteName: suite).isOn(.torrentsKeepSharing))
        print("PASS: torrent module lifecycle, defaults, gating, magnet/file routing and policy injection")
    }

    struct FakeTool: TorrentToolLocating {
        let url: URL
        func aria2c() -> URL? { url }
    }

    static func processLifecycle() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TORRENT_TEST_ROOT"]
            ?? FileManager.default.temporaryDirectory.path).appending(path: "fake-aria2-module-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appending(path: "aria2c")
        try "#!/bin/sh\nexit 1\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        let suite = "torrent-process-module.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let session = TorrentAria2Session(stateDirectory: root.appending(path: "state"), locator: FakeTool(url: tool))
        let module = TorrentModule(session: session, preferences: preferences, destination: root,
                                  locator: FakeTool(url: tool), readInterfaces: { [] })
        let controller = NotchcastModuleController([.init(requires: [.torrents], module: module)],
                                                  preferences: preferences)
        controller.run()
        await module.refreshTool()
        precondition(module.toolURL == tool && module.isRunning)
        precondition(module.open(URL(string: "magnet:?xt=urn:btih:" + String(repeating: "b", count: 40))!))
        try await until("fake executable failure") { module.manager.jobs.first?.state == .failed }
        preferences.set(.torrents, false)
        try await until("fake executable module stops") { !module.isRunning }
        await module.manager.stop()
        precondition(!session.isAlive)
        preferences.set(.torrents, true)
        try await until("fake executable module restarts") { module.isRunning }
        module.stop()
        await module.manager.stop()
        let core = AppCore()
        precondition(!core.handleTorrentURL(URL(string: "https://example.invalid")!))
        let entries = TorrentModule.register()
        precondition(entries.count == 1 && entries[0].requires == [.torrents] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === TorrentModule.shared)
        let shared = TorrentModule.shared.preferences
        let original = shared.isOn(.torrents)
        defer { shared.set(.torrents, original) }
        shared.set(.torrents, false)
        precondition(core.handleTorrentURL(URL(fileURLWithPath: "/fixture/test.torrent")))
        precondition(core.messages.count == 1)
        print("PASS: production entries and fake aria2c process start, failure, stop and toggle; no network")
    }
}
