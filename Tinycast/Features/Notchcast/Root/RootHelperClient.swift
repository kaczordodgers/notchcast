import Foundation
import Synchronization

struct RootHelperClient: Sendable {
    enum Failure: Error, Equatable {
        case unsafePath(RootToolPath.Problem)
        case launchFailed
        case authorizationRequired
        case reinstallRequired
        case executionFailed(Int32)
        case timedOut
        case invalidResponse
    }

    var isInstalled: Bool { RootToolPath.verify() == nil }

    @concurrent
    func clean(_ command: RootContract.Command, input: Data) async throws -> Data {
        guard [.version, .cleanSystemList, .cleanSystemTrash].contains(command)
        else { throw Failure.invalidResponse }
        return try await execute(command, input: input)
    }

    @concurrent
    private func execute(_ command: RootContract.Command, input: Data) async throws -> Data {
        try Task.checkCancellation()
        try Self.refuseWhileAbandonedRuns()
        if let problem = RootToolPath.verify() { throw Failure.unsafePath(problem) }
        guard input.count <= 4096
        else { throw Failure.invalidResponse }
        let directory = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: directory, withIntermediateDirectories: false,
                                         attributes: [.posixPermissions: 0o700])
        defer { try? FileManager().removeItem(at: directory) }
        let destination = directory.appendingPathComponent("reply")
        FileManager().createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let source = directory.appendingPathComponent("request")
        try input.write(to: source)
        let request = try FileHandle(forReadingFrom: source)
        defer { try? request.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", RootContract.helperPath] + command.arguments
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = request
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exit: ProcessExit
        do { exit = try process.runObservingExit() }
        catch { throw Failure.launchFailed }
        do {
            try await Self.wait(for: process, exit: exit, timeout: command.operation.timeout)
        } catch {
            Self.abandoned.withLock { $0.append(process) }
            throw error
        }
        guard process.terminationReason == .exit else {
            throw Failure.executionFailed(process.terminationStatus)
        }
        try Self.validateExitStatus(process.terminationStatus)
        try Task.checkCancellation()
        return try Data(contentsOf: destination)
    }

    /// Root children we stopped waiting for; root tools must not overlap, so no new one starts while one runs.
    private static let abandoned = Mutex<[Process]>([])

    static func refuseWhileAbandonedRuns() throws {
        try abandoned.withLock { children in
            children.removeAll { !$0.isRunning }
            if !children.isEmpty { throw Failure.timedOut }
        }
    }

    @concurrent
    func run(_ command: RootContract.Command) async throws -> RootContract.Reply {
        let data = try await execute(command, input: Data())
        guard data.count <= 4096, let text = String(bytes: data, encoding: .utf8),
              let reply = RootContract.Reply(command: command, output: text)
        else { throw Failure.invalidResponse }
        return reply
    }

    func run(_ command: RootContract.Command, process: Process, exit: ProcessExit,
             output: Pipe, timeout: Duration) async throws -> RootContract.Reply {
        do {
            try await Self.wait(for: process, exit: exit, timeout: timeout)
        } catch {
            Self.abandoned.withLock { $0.append(process) }
            throw error
        }
        guard process.terminationReason == .exit else {
            throw Failure.executionFailed(process.terminationStatus)
        }
        try Self.validateExitStatus(process.terminationStatus)
        let data: Data
        do {
            data = try output.fileHandleForReading.read(upToCount: 4_097) ?? Data()
        } catch {
            throw Failure.invalidResponse
        }
        guard data.count <= 4_096,
              let text = String(bytes: data, encoding: .utf8),
              let reply = RootContract.Reply(command: command, output: text)
        else { throw Failure.invalidResponse }
        try Task.checkCancellation()
        return reply
    }

    static func validateExitStatus(_ status: Int32) throws {
        switch status {
        case 0: return
        case 1: throw Failure.authorizationRequired
        case RootContract.unauthorizedCallerExit: throw Failure.reinstallRequired
        default: throw Failure.executionFailed(status)
        }
    }

    static func wait(for process: Process, exit: ProcessExit, timeout: Duration) async throws {
        try await RootWait.perform(timeout: timeout) {
            await reap(exit)
        }
    }

    private static func reap(_ exit: ProcessExit) async {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                exit.wait()
                continuation.resume()
            }
        }
    }
}
