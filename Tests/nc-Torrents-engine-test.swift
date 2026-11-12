// notchcast-sources: Tinycast/Features/Torrents/Model/*.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentAria2Session.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentManager.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentQueueHost.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentRPCClient.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentSession.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentStatus.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentSubmission.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentToolLocating.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/TorrentToolLocator.swift
// notchcast-kit: platform
import CryptoKit
import Darwin
import Foundation

@main struct TorrentEngineTests {
    @MainActor final class FakeSession: TorrentSession {
        var isAlive = false
        var starts = 0
        var stops = 0
        var arguments: [String] = []
        var submissions: [TorrentSubmission] = []
        var sharing: [Bool] = []
        var removed: [String] = []
        var statuses: [String: TorrentStatus] = [:]
        var failure: TorrentFailure?
        var rejectedHashes = Set<String>()
        var vanishedGIDs = Set<String>()
        var addContinuation: CheckedContinuation<String, Never>?
        var suspendAdd = false
        var statusContinuation: CheckedContinuation<TorrentStatus, Never>?
        var suspendStatus = false

        func start(extraArguments: [String]) async throws {
            if let failure { throw failure }
            starts += 1
            isAlive = true
            arguments = extraArguments
        }

        func add(_ submission: TorrentSubmission, destination: URL, keepSharing: Bool) async throws -> String {
            if rejectedHashes.contains(submission.infoHash) { throw TorrentFailure.rpc(code: 1, message: "rejected") }
            submissions.append(submission)
            sharing.append(keepSharing)
            let gid = String(submissions.count)
            statuses[gid] = TorrentStatus(status: "active")
            if suspendAdd { return await withCheckedContinuation { addContinuation = $0 } }
            return gid
        }

        func status(_ gid: String) async throws -> TorrentStatus {
            if vanishedGIDs.contains(gid) { throw TorrentFailure.rpc(code: 1, message: "GID not found") }
            if let failure { throw failure }
            if suspendStatus { return await withCheckedContinuation { statusContinuation = $0 } }
            return statuses[gid] ?? TorrentStatus(status: "removed")
        }

        func remove(_ gid: String) async throws {
            removed.append(gid)
            if vanishedGIDs.contains(gid) { throw TorrentFailure.rpc(code: 1, message: "GID not found") }
            statuses[gid] = TorrentStatus(status: "removed")
        }

        func stop() async { stops += 1; isAlive = false }
        func terminate() {}
    }

    struct MissingTool: TorrentToolLocating { func aria2c() -> URL? { nil } }
    struct FakeTool: TorrentToolLocating {
        let url: URL
        func aria2c() -> URL? { url }
    }

    @MainActor static var checks = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { fatalError(message) }
    }

    @MainActor static func until(_ message: String, timeout: Duration = .seconds(60), _ predicate: () -> Bool) async throws {
        // A wedged wait fails by name instead of running into the suite's 300 s kill.
        let deadline = ContinuousClock.now + timeout
        while !predicate() {
            guard ContinuousClock.now < deadline else { fatalError("Timed out: \(message)") }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(true, message)
    }

    static func torrent(name: String, payload: Data) -> Data {
        let pieceLength = 16384
        var pieces = Data()
        for start in stride(from: 0, to: payload.count, by: pieceLength) {
            pieces.append(contentsOf: Insecure.SHA1.hash(data: payload[start..<min(start + pieceLength, payload.count)]))
        }
        var result = Data("d4:infod6:lengthi\(payload.count)e4:name\(name.utf8.count):\(name)".utf8)
        result.append(Data("12:piece lengthi16384e6:pieces\(pieces.count):".utf8))
        result.append(pieces)
        result.append(Data("7:privatei1eee".utf8))
        return result
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TORRENT_TEST_ROOT"]
            ?? FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = torrent(name: "fixture.bin", payload: Data(repeating: 65, count: 32768))
        let file = root.appendingPathComponent("fixture.torrent")
        try data.write(to: file)
        let submission = try await TorrentSubmission.read(file)
        let hash = submission.infoHash
        guard let magnet = URL(string: "magnet:?xt=urn:btih:\(hash)&dn=ignored") else { fatalError("Magnet") }
        try modelChecks(data: data, hash: hash)
        try await managerChecks(file: file, magnet: magnet, root: root)
        try await cancellationChecks(magnet: magnet, root: root)
        try await failureChecks(magnet: magnet, root: root)
        try await batchChecks(root: root)
        try await rpcChecks(root: root)
        try await sessionChecks(root: root)
        try await smoke(file: file, root: root)
        print("PASS: \(checks) torrent parsing, lifecycle, progress, cancellation, retry and RPC checks")
    }

    @MainActor static func modelChecks(data: Data, hash: String) throws {
        check(try TorrentMetainfo.read(data).name == "fixture.bin", "Bencoded metadata name")
        let uppercase = URL(string: "magnet:?xt=urn:btih:\(hash.uppercased())")
        check(try uppercase.map(TorrentMetainfo.magnetHash) == hash, "Hex hash case is normalized")
        let base32 = URL(string: "magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        check(try base32.map(TorrentMetainfo.magnetHash) == String(repeating: "0", count: 40), "Base32 hashes")
        for malformed in ["", "de", "d4:infolee", "d4:infod4:name9999999999:xe", "d1:ai0e1:ai1ee",
                          "d4:infod4:name1:xe4:infolee", "d4:infod4:name1:xeex", "d1:al" + String(repeating: "l", count: 65)] {
            do {
                _ = try TorrentMetainfo.read(Data(malformed.utf8))
                fatalError("Malformed torrent accepted")
            } catch TorrentFailure.invalidTorrent { check(true, "Malformed torrent rejected") }
        }
        for malformed in ["https://example.invalid/file", "magnet:?dn=name", "magnet:?xt=urn:btih:xyz",
                          "magnet:?xt=urn:btih:\(hash)&xt=urn:btih:\(hash)"] {
            guard let url = URL(string: malformed) else { fatalError("Fixture URL") }
            do {
                _ = try TorrentMetainfo.magnetHash(url)
                fatalError("Invalid magnet accepted")
            } catch TorrentFailure.invalidInput { check(true, "Invalid magnet rejected") }
        }
    }

    @MainActor static func managerChecks(file: URL, magnet: URL, root: URL) async throws {
        try Data([65]).write(to: root.appendingPathComponent("fixture.bin"))
        let session = FakeSession()
        var date = Date(timeIntervalSince1970: 0)
        var revealed: [URL] = []
        var argumentReads = 0
        let manager = TorrentManager(session: session, destination: root, extraArguments: {
            argumentReads += 1
            return ["--multiple-interface=en0,en7"]
        }, now: { date }, pollInterval: .milliseconds(10), revealFiles: { revealed = $0 })
        let ids = manager.enqueue([file, magnet])
        try await until("Same info hash is rejected across torrent and magnet") { manager.jobs[1].error == .alreadyRunning }
        check(session.starts == 1 && session.submissions.count == 1, "One child and one admission")
        check(session.arguments == ["--multiple-interface=en0,en7"] && argumentReads == 1, "Injected interface policy")
        session.statuses["1"] = TorrentStatus(status: "active", totalLength: "1000", completedLength: "250",
                                              downloadSpeed: "50", connections: "3", numSeeders: "2")
        try await until("Progress updates") { manager.jobs[0].bytesDone == 250 }
        check(manager.jobs[0].timeLeft == 15 && manager.jobs[0].peers == 3 && manager.jobs[0].seeders == 2, "ETA and peers")
        session.statuses["1"] = TorrentStatus(status: "active", totalLength: "1000", completedLength: "1000", seeder: "true")
        try await until("Seeding is observable") { manager.jobs[0].state == .sharing }
        date = date.addingTimeInterval(1000)
        try await Task.sleep(for: .milliseconds(40))
        check(manager.jobs[0].state == .sharing, "Sharing does not fail for no peers")
        session.statuses["1"] = TorrentStatus(status: "complete", totalLength: "1000", completedLength: "1000",
                                              files: [.init(path: root.appendingPathComponent("fixture.bin").path)])
        try await until("Finished and idle shutdown") { manager.jobs[0].state == .finished && session.stops > 0 }
        manager.reveal(ids[0])
        let expectedPath = root.appendingPathComponent("fixture.bin").standardizedFileURL.path
        check(revealed.map(\.standardizedFileURL.path) == [expectedPath],
              "Reveal uses owned output paths: \(revealed)")
        let next = manager.enqueue([magnet], keepSharing: true)
        try await until("Restart after idle") { session.submissions.count == 2 }
        check(session.starts == 2 && session.sharing == [false, true], "Sharing opt-in survives admission")
        check(manager.jobs.last?.name == nil && manager.jobs.last?.state == .findingPeers, "Magnet placeholder is semantic")
        session.statuses["2"] = TorrentStatus(status: "complete", followedBy: ["payload"])
        session.statuses["payload"] = TorrentStatus(status: "active", totalLength: "2000", completedLength: "100",
            downloadSpeed: "100", connections: "1", bittorrent: .init(info: .init(name: "metadata.bin")))
        try await until("Magnet follows payload GID") { manager.jobs.last?.name == "metadata.bin" }
        check(manager.jobs.last?.state == .downloading, "Metadata completion is not download completion")
        manager.cancel(next[0])
        try await until("Cancel removes payload") { session.removed.contains("payload") }
        check(manager.jobs.last?.state == .cancelled, "Cancellation retained")
        let retry = manager.tryAgain(next[0])
        check(retry != nil && retry != next[0], "Retry gets fresh operation identity")
        check(manager.jobs.count == 3, "Retry replaces its row")
        try await until("Retry admitted") { session.submissions.count == 3 }
        date = date.addingTimeInterval(599)
        try await Task.sleep(for: .milliseconds(40))
        check(manager.jobs.last?.state.isRunning == true, "No-peer deadline boundary")
        date = date.addingTimeInterval(1)
        try await until("Ten minutes without peers fails") { manager.jobs.last?.error == .noPeers }
        await manager.stop()
        check(manager.jobs[0].state == .finished, "Stop preserves completed values")
        manager.dismiss(ids[0])
        check(!manager.jobs.contains { $0.id == ids[0] }, "Dismiss removes terminal row")
    }

    @MainActor static func cancellationChecks(magnet: URL, root: URL) async throws {
        let session = FakeSession()
        session.suspendAdd = true
        let manager = TorrentManager(session: session, destination: root, pollInterval: .milliseconds(10))
        let ids = manager.enqueue([magnet])
        try await until("Add suspended") { session.addContinuation != nil }
        manager.cancel(ids[0])
        session.suspendAdd = false
        session.addContinuation?.resume(returning: "1")
        session.addContinuation = nil
        try await until("Late admission is removed") { session.removed.contains("1") }
        check(manager.jobs[0].state == .cancelled, "Late add cannot resurrect cancellation")
        _ = manager.tryAgain(ids[0])
        try await until("Retry after cancelled add") { session.submissions.count == 2 }
        session.suspendStatus = true
        try await until("Status suspended") { session.statusContinuation != nil }
        manager.cancel(manager.jobs[0].id)
        session.suspendStatus = false
        session.statusContinuation?.resume(returning: TorrentStatus(status: "complete"))
        session.statusContinuation = nil
        try await until("Late status cleaned up") { session.removed.contains("2") }
        check(manager.jobs[0].state == .cancelled, "Late completion cannot resurrect cancellation")
        await manager.stop()
    }

    @MainActor static func failureChecks(magnet: URL, root: URL) async throws {
        let session = FakeSession()
        session.failure = .toolNotInstalled
        let manager = TorrentManager(session: session, destination: root, pollInterval: .milliseconds(10))
        manager.enqueue([magnet])
        try await until("Missing tool is typed") { manager.jobs[0].error == .toolNotInstalled }
        await manager.stop()
        session.failure = nil
        _ = manager.tryAgain(manager.jobs[0].id)
        try await until("Failed job retries") { session.submissions.count == 1 }
        session.statuses["1"] = TorrentStatus(status: "error", errorCode: "3", errorMessage: "fixture failure")
        try await until("Aria2 error retained") {
            manager.jobs.last?.error == .download(code: "3", message: "fixture failure")
        }
        await manager.stop()
        let missing = TorrentAria2Session(stateDirectory: root.appendingPathComponent("missing"), locator: MissingTool())
        do {
            try await missing.start(extraArguments: [])
            fatalError("Missing tool accepted")
        } catch TorrentFailure.toolNotInstalled { check(missing.processIdentifier == nil, "No fallback process") }
    }

    @MainActor static func batchChecks(root: URL) async throws {
        let hashes = (1...3).map { String(repeating: "0", count: 39) + String($0) }
        let urls = hashes.compactMap { URL(string: "magnet:?xt=urn:btih:\($0)") }
        let session = FakeSession()
        session.rejectedHashes.insert(hashes[1])
        let manager = TorrentManager(session: session, destination: root, pollInterval: .milliseconds(10))
        let ids = manager.enqueue(urls)
        try await until("Several inputs share one process") { session.submissions.count == 2 }
        check(session.starts == 1 && manager.jobs[1].error == .rpc(code: 1, message: "rejected"),
              "One refused admission leaves other jobs running")
        manager.cancel(ids[0])
        try await until("One job cancels independently") { session.removed.contains("1") }
        check(manager.jobs[2].state.isRunning && session.stops == 0, "Child stays alive for remaining torrent")
        session.failure = .rpcUnavailable
        try await Task.sleep(for: .milliseconds(100))
        check(manager.jobs[2].state.isRunning && session.stops == 0, "Transport failures preserve living child and jobs")
        session.failure = nil
        session.vanishedGIDs.insert("2")
        let fourth = URL(string: "magnet:?xt=urn:btih:" + String(repeating: "4", count: 40))!
        manager.enqueue([fourth])
        try await until("Vanished status fails only that job") { manager.jobs[2].state == .failed }
        try await until("Benign remove race preserves other job") { session.removed.contains("2") }
        check(manager.jobs[3].state.isRunning && session.stops == 0, "RPC job error preserves child")
        session.failure = .rpcUnavailable
        session.isAlive = false
        try await until("Dead child fails remaining jobs") { manager.jobs[3].error == .rpcUnavailable }
        await manager.stop()
    }

    @MainActor static func sessionChecks(root: URL) async throws {
        let tool = root.appendingPathComponent("fake-aria2")
        let source = """
        #!/usr/bin/env node
        const fs = require('node:fs'), http = require('node:http');
        if (process.env.PATH.split(':')[0] !== require('node:path').dirname(process.argv[1])) process.exit(9);
        const option = name => process.argv.find(arg => arg.startsWith(name + '='))?.split('=')[1];
        const root = option('--fixture-root'), owner = Number(option('--stop-with-process'));
        fs.writeFileSync(root + '/pid', String(process.pid));
        for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
          fs.appendFileSync(root + '/signals', signal + ' ' + Date.now() + '\\n');
        });
        if (!fs.existsSync(root + '/descendant')) {
          const descendant = require('node:child_process').spawn(process.execPath, ['-e',
          `setInterval(() => { try { process.kill(${owner}, 0); } catch { process.exit(); } }, 100);`
          ], {stdio: 'ignore'});
          fs.writeFileSync(root + '/descendant', String(descendant.pid));
        }
        const server = http.createServer((request, response) => {
          let body = '';
          request.on('data', chunk => { body += chunk; });
          request.on('end', () => {
            const message = JSON.parse(body);
            const valid = message.method === 'aria2.getSessionInfo' &&
              message.params[0] === 'token:' + option('--rpc-secret');
            response.end(JSON.stringify({jsonrpc: '2.0', id: message.id,
              result: valid ? {sessionId: 'fixture'} : null}));
          });
        });
        server.listen(Number(option('--rpc-listen-port')), '127.0.0.1');
        setInterval(() => { try { process.kill(owner, 0); } catch { process.exit(); } }, 100).unref();
        """
        try source.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        let locator = FakeTool(url: tool)
        let arguments = ["--fixture-root=\(root.path)"]
        var session: TorrentAria2Session? = TorrentAria2Session(stateDirectory: root, locator: locator)
        try await session!.start(extraArguments: arguments)
        let pid = session!.processIdentifier!
        let fixturePID = try String(contentsOf: root.appendingPathComponent("pid"), encoding: .utf8)
        check(String(pid) == fixturePID && session!.isAlive && kill(pid, 0) == 0, "Real session owns live fixture PID")
        try await session!.start(extraArguments: [])
        check(session!.processIdentifier == pid, "Repeated start keeps the same process")
        let descendantText = try String(contentsOf: root.appendingPathComponent("descendant"), encoding: .utf8)
        let descendant = Int32(descendantText)!
        defer { kill(descendant, SIGKILL) }
        let stopped = ContinuousClock.now
        await session!.stop()
        let elapsed = stopped.duration(to: .now)
        check(!session!.isAlive && session!.processIdentifier == nil && kill(pid, 0) == -1 && errno == ESRCH,
              "Stop awaits reaping and clears the handle")
        let signals = try String(contentsOf: root.appendingPathComponent("signals"), encoding: .utf8)
            .split(separator: "\n").map { $0.split(separator: " ") }
        check(signals.map { String($0[0]) } == ["SIGINT", "SIGTERM"], "Stop delivers INT then TERM")
        check(Int64(signals[1][1])! - Int64(signals[0][1])! >= 900 && elapsed >= .milliseconds(1800)
            && elapsed < .milliseconds(2800), "Stop waits for TERM at 1 s and KILL at 2 s")
        check(kill(descendant, 0) == 0, "Aria2 stop signals only its PID")
        try await session!.start(extraArguments: arguments)
        let terminated = session!.processIdentifier!
        session!.terminate()
        try await until("Immediate terminate reaps child", timeout: .seconds(1)) { kill(terminated, 0) == -1 && errno == ESRCH }
        await session!.stop()
        try await session!.start(extraArguments: arguments)
        let released = session!.processIdentifier!
        weak var weakSession = session
        session = nil
        check(weakSession == nil, "Running handle does not retain its session")
        try await until("Deinit reaps child", timeout: .seconds(1)) { kill(released, 0) == -1 && errno == ESRCH }
        let missing = TorrentAria2Session(stateDirectory: root,
            locator: FakeTool(url: root.appendingPathComponent("missing-executable")))
        do {
            try await missing.start(extraArguments: [])
            fatalError("Missing executable started")
        } catch TorrentFailure.launchFailed {
            check(!missing.isAlive && missing.processIdentifier == nil, "Launch failure stays typed and owns no PID")
        }
        print("PASS: real session PID, liveness, INT/TERM/KILL timing, PID-only stop, terminate, deinit, launch failure")
    }

    @MainActor static func rpcChecks(root: URL) async throws {
        let script = root.appendingPathComponent("rpc-stub.mjs")
        let portFile = root.appendingPathComponent("rpc-port")
        let source = """
        import http from 'node:http';
        import fs from 'node:fs';
        const server = http.createServer((request, response) => {
          let body = '';
          request.on('data', chunk => { body += chunk; });
          request.on('end', () => {
            const message = JSON.parse(body);
            if (message.method === 'aria2.hang') return;
            if (message.method === 'aria2.redirect') {
              response.writeHead(302, {Location: '/redirected'});
              response.end(); return;
            }
            const reply = {jsonrpc: '2.0', id: message.id};
            if (message.method === 'aria2.error') reply.error = {code: 1, message: 'fixture'};
            else if (message.method === 'aria2.badID') { reply.id = 'wrong'; reply.result = 'bad'; }
            else reply.result = message.params;
            response.setHeader('Content-Type', 'application/json');
            if (reply.error) response.statusCode = 400;
            response.end(JSON.stringify(reply));
          });
        });
        server.listen(0, '127.0.0.1', () => fs.writeFileSync(process.argv[2], String(server.address().port)));
        setInterval(() => { try { process.kill(Number(process.argv[3]), 0); } catch { process.exit(); } }, 100).unref();
        """
        try Data(source.utf8).write(to: script)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["node", script.path, portFile.path, String(getpid())]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        let exit = try child.runObservingExit()
        do {
            try await until("Loopback stub starts") { FileManager.default.fileExists(atPath: portFile.path) }
            let text = try String(contentsOf: portFile, encoding: .utf8)
            guard let port = UInt16(text) else { fatalError("Stub port") }
            let secret = UUID().uuidString
            let client = TorrentRPCClient(port: port, secret: secret)
            defer { client.invalidate() }
            let echo: [String] = try await client.call("echo", parameters: ["payload"])
            check(echo == ["token:\(secret)", "payload"], "RPC authenticates and preserves parameters")
            do {
                let _: String = try await client.call("error")
                fatalError("RPC error accepted")
            } catch TorrentFailure.rpc(let code, let message) {
                check(code == 1 && message == "fixture", "RPC error is typed")
            }
            for method in ["badID", "redirect"] {
                do {
                    let _: String = try await client.call(method)
                    fatalError("Invalid response accepted")
                } catch TorrentFailure.invalidResponse { check(true, "Invalid response rejected") }
            }
            let pending = Task { let _: String = try await client.call("hang") }
            try await Task.sleep(for: .milliseconds(50))
            pending.cancel()
            do {
                try await pending.value
                fatalError("Cancelled RPC accepted")
            } catch is CancellationError { check(true, "RPC cancellation propagates") }
        } catch {
            child.terminate()
            await reap(exit)
            throw error
        }
        child.terminate()
        await reap(exit)
        print("PASS: fake loopback RPC server, token authentication, errors, IDs, redirects and cancellation")
    }

    @concurrent static func reap(_ exit: ProcessExit) async { exit.wait() }

    @MainActor static func smoke(file: URL, root: URL) async throws {
        guard TorrentToolLocator().aria2c() != nil else {
            print("SKIP: real aria2c smoke: aria2c not installed")
            return
        }
        let destination = root.appendingPathComponent("download")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 32768).write(to: destination.appendingPathComponent("fixture.bin"))
        let session = TorrentAria2Session(stateDirectory: root.appendingPathComponent("aria2-state"))
        let offline = ["--enable-dht=false", "--enable-dht6=false", "--bt-enable-lpd=false",
                       "--bt-exclude-tracker=*", "--interface=127.0.0.1"]
        let manager = TorrentManager(session: session, destination: destination, extraArguments: { offline },
                                     pollInterval: .milliseconds(100))
        var large = Data("d7:comment1600000:".utf8)
        large.append(Data(repeating: 65, count: 1_600_000))
        large.append(try Data(contentsOf: file).dropFirst())
        let largeFile = root.appendingPathComponent("large.torrent")
        try large.write(to: largeFile)
        manager.enqueue([largeFile])
        try await until("Real loopback RPC finishes local torrent") { !manager.jobs[0].state.isRunning }
        check(manager.jobs[0].state == .finished,
              "Real aria2 accepts 1.6 MB torrent: \(String(describing: manager.jobs[0].error))")
        let quarantine = getxattr(destination.appendingPathComponent("fixture.bin").path,
                                  "com.apple.quarantine", nil, 0, 0, 0)
        check(quarantine > 0, "Completed local torrent is quarantined")
        try await until("Real child exits when idle") { session.processIdentifier == nil }
        let incomplete = root.appendingPathComponent("incomplete.torrent")
        try torrent(name: "incomplete.bin", payload: Data(repeating: 66, count: 65536)).write(to: incomplete)
        let ids = manager.enqueue([incomplete])
        try await until("Real incomplete torrent admitted") { manager.jobs[1].state == .downloading }
        guard let pid = session.processIdentifier else { fatalError("Owned child PID") }
        try await until("Control file saved") {
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("incomplete.bin.aria2").path)
        }
        manager.cancel(ids[0])
        try await until("Cancelled child exits") { session.processIdentifier == nil }
        check(kill(pid, 0) == -1 && errno == ESRCH, "No orphaned process")
        check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("incomplete.bin.aria2").path),
              "Cancellation preserves resume control file")
        _ = manager.tryAgain(ids[0])
        try await until("Real retry resumes") { manager.jobs.last?.state == .downloading }
        await manager.stop()
        check(session.processIdentifier == nil && manager.jobs.last?.state == .cancelled, "Stop reaps resumed child")
        print("PASS: real aria2c, PID-verified loopback RPC, private tracker-free local torrent, no internet downloads")
    }
}
