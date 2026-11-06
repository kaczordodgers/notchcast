import Foundation
import Darwin
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", RootContract.helperPath] + command.arguments
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardError = FileHandle.nullDevice
        return try await exchange(process: process, input: input, timeout: command.operation.timeout)
    }

    @concurrent
    func exchange(process: Process, input: Data, timeout: Duration) async throws -> Data {
        let request = Pipe()
        let output = Pipe()
        process.standardInput = request
        process.standardOutput = output
        guard fcntl(request.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0
        else { throw Failure.launchFailed }
        defer { try? request.fileHandleForWriting.close() }
        defer { try? output.fileHandleForReading.close() }
        let exit: ProcessExit
        do { exit = try process.runObservingExit() }
        catch { throw Failure.launchFailed }
        let reader = Task.detached { try output.fileHandleForReading.readToEnd() ?? Data() }
        do {
            try request.fileHandleForWriting.write(contentsOf: input)
            try request.fileHandleForWriting.close()
            try await Self.wait(for: process, exit: exit, timeout: timeout)
        } catch {
            Self.abandoned.withLock { $0.append(process) }
            throw error
        }
        guard process.terminationReason == .exit else {
            throw Failure.executionFailed(process.terminationStatus)
        }
        try Self.validateExitStatus(process.terminationStatus)
        try Task.checkCancellation()
        return try await reader.value
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
