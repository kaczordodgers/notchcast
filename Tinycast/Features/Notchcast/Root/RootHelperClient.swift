import Foundation

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
    func run(_ command: RootContract.Command) async throws -> RootContract.Reply {
        try Task.checkCancellation()
        if let problem = RootToolPath.verify() { throw Failure.unsafePath(problem) }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", RootContract.helperPath] + command.arguments
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exit: ProcessExit
        try Task.checkCancellation()
        do {
            exit = try process.runObservingExit()
        } catch {
            throw Failure.launchFailed
        }
        try await Self.wait(for: process, exit: exit, timeout: command.operation.timeout)
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
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { await reap(exit) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw Failure.timedOut
                }
                defer { group.cancelAll() }
                do {
                    try await group.next()
                    try Task.checkCancellation()
                } catch {
                    if process.isRunning { process.terminate() }
                    throw error
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
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
