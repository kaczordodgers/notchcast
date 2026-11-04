import Darwin
import Foundation

@MainActor final class TorrentAria2Session: TorrentSession {
    private struct SessionInfo: Decodable, Sendable { let sessionId: String }

    private let locator: any TorrentToolLocating
    private let stateDirectory: URL
    private var process: Process?
    private var exit: ProcessExit?
    private var client: TorrentRPCClient?

    var processIdentifier: Int32? { process?.processIdentifier }
    var isAlive: Bool { process?.isRunning == true }

    init(stateDirectory: URL, locator: any TorrentToolLocating = TorrentToolLocator()) {
        self.stateDirectory = stateDirectory
        self.locator = locator
    }

    isolated deinit {
        client?.invalidate()
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func terminate() {
        client?.invalidate()
        client = nil
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func start(extraArguments: [String]) async throws {
        if let process {
            guard process.isRunning else { throw TorrentFailure.launchFailed }
            return
        }
        let executable = try await Self.prepare(locator: locator, directory: stateDirectory)
        try Task.checkCancellation()
        let port = try Self.freePort()
        let secret = UUID().uuidString + UUID().uuidString
        let child = Process()
        child.executableURL = executable
        child.arguments = Self.arguments(port: port, secret: secret, stateDirectory: stateDirectory,
                                         extraArguments: extraArguments)
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            exit = try child.runObservingExit()
        } catch {
            throw TorrentFailure.launchFailed
        }
        process = child
        do {
            var verified = false
            for _ in 0..<40 {
                try Task.checkCancellation()
                guard child.isRunning else { throw TorrentFailure.launchFailed }
                if try await Self.ownsListener(pid: child.processIdentifier, port: port) {
                    verified = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard verified else { throw TorrentFailure.listenerNotOwned }
            try Task.checkCancellation()
            let rpc = TorrentRPCClient(port: port, secret: secret)
            client = rpc
            let _: SessionInfo = try await rpc.call("getSessionInfo")
        } catch {
            await stop()
            throw error
        }
    }

    func add(_ submission: TorrentSubmission, destination: URL, keepSharing: Bool) async throws -> String {
        guard let client, process?.isRunning == true else { throw TorrentFailure.rpcUnavailable }
        var options = ["dir": destination.path, "continue": "true", "seed-ratio": "1.0"]
        if !keepSharing { options["seed-time"] = "0" }
        switch submission.payload {
        case .torrent(let data):
            return try await client.call("addTorrent", parameters: [data.base64EncodedString(), [String](), options])
        case .magnet(let url):
            return try await client.call("addUri", parameters: [[url.absoluteString], options])
        }
    }

    func status(_ gid: String) async throws -> TorrentStatus {
        guard let client, process?.isRunning == true else { throw TorrentFailure.rpcUnavailable }
        return try await client.call("tellStatus", parameters: [gid, [
            "status", "totalLength", "completedLength", "downloadSpeed", "connections", "numSeeders",
            "seeder", "errorCode", "errorMessage", "infoHash", "followedBy", "files", "bittorrent",
        ]])
    }

    func remove(_ gid: String) async throws {
        guard let client else { throw TorrentFailure.rpcUnavailable }
        let current = try await status(gid)
        if ["active", "waiting", "paused"].contains(current.status) {
            let _: String = try await client.call("forceRemove", parameters: [gid])
        }
        for child in current.followedBy ?? [] { try await remove(child) }
    }

    func stop() async {
        client?.invalidate()
        client = nil
        guard let child = process else { return }
        if child.isRunning { child.interrupt() }
        await Self.waitBriefly(child)
        if child.isRunning { child.terminate() }
        await Self.waitBriefly(child)
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        if let exit { await Self.reap(exit) }
        process = nil
        exit = nil
    }

    static func arguments(port: UInt16, secret: String, stateDirectory: URL, extraArguments: [String]) -> [String] {
        extraArguments + [
            "--no-conf=true", "-j16", "--bt-max-peers=200", "--bt-request-peer-speed-limit=1024M",
            "-x16", "-s16", "-k1M", "--follow-torrent=mem", "--bt-save-metadata=false",
            "--file-allocation=none", "--dht-entry-point=dht.transmissionbt.com:6881",
            "--continue=true", "--auto-file-renaming=false", "--allow-overwrite=false", "--check-integrity=true",
            "--auto-save-interval=1", "--seed-ratio=1.0", "--rpc-save-upload-metadata=false",
            "--dht-file-path=\(stateDirectory.appendingPathComponent("dht.dat").path)",
            "--dht-file-path6=\(stateDirectory.appendingPathComponent("dht6.dat").path)",
            "--enable-rpc=true", "--rpc-max-request-size=32M", "--rpc-listen-all=false", "--rpc-allow-origin-all=false",
            "--rpc-listen-port=\(port)", "--rpc-secret=\(secret)", "--disable-ipv6=true",
            "--stop-with-process=\(getpid())", "--daemon=false", "--quiet=true",
        ]
    }

    @concurrent private static func prepare(locator: any TorrentToolLocating, directory: URL) async throws -> URL {
        guard let executable = locator.aria2c() else { throw TorrentFailure.toolNotInstalled }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        } catch {
            throw TorrentFailure.launchFailed
        }
        return executable
    }

    private static func freePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw TorrentFailure.launchFailed }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
        }
        guard bound == 0 else { throw TorrentFailure.launchFailed }
        let read = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard read == 0 else { throw TorrentFailure.launchFailed }
        return UInt16(bigEndian: address.sin_port)
    }

    @concurrent private static func ownsListener(pid: Int32, port: UInt16) async throws -> Bool {
        let command = Process()
        let output = Pipe()
        command.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        command.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpn"]
        command.standardOutput = output
        command.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let exit = try command.runObservingExit()
            try? output.fileHandleForWriting.close()
            defer { try? output.fileHandleForReading.close() }
            if Task.isCancelled, command.isRunning { kill(command.processIdentifier, SIGKILL) }
            exit.wait()
            try Task.checkCancellation()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { throw TorrentFailure.listenerNotOwned }
            let lines = text.split(separator: "\n").map(String.init)
            let listeners = lines.filter { $0.hasPrefix("n") }
            return command.terminationStatus == 0 && lines.contains("p\(pid)")
                && listeners == ["n127.0.0.1:\(port)"]
        } onCancel: {
            if command.isRunning { kill(command.processIdentifier, SIGKILL) }
        }
    }

    private static func waitBriefly(_ process: Process) async {
        for _ in 0..<10 where process.isRunning {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
    }

    @concurrent private static func reap(_ exit: ProcessExit) async { exit.wait() }
}
