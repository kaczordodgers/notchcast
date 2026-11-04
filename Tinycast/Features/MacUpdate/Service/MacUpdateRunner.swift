import Foundation
import Darwin

@MainActor
protocol MacUpdateProcessRunning {
    func run(_ command: MacUpdateCommand) async throws -> MacUpdateRunner.Result
}

@MainActor
struct MacUpdateRunner: MacUpdateProcessRunning {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var timedOut = false
    }

    func run(_ command: MacUpdateCommand) async throws -> Result {
        precondition(command.path.hasPrefix("/"))
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        var bytes = Data()
        process.executableURL = URL(filePath: command.path)
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw POSIXError(.EIO)
        }
        func drain() {
            var buffer = [UInt8](repeating: 0, count: 8192)
            for _ in 0..<16 {
                let count = read(descriptor, &buffer, buffer.count)
                guard count > 0 else { return }
                bytes.append(contentsOf: buffer.prefix(count))
                if bytes.count > 65536 { bytes.removeFirst(bytes.count - 65536) }
            }
        }
        let exit = try process.runObservingExit()
        let deadline = ContinuousClock.now + command.timeout
        while process.isRunning && !Task.isCancelled && ContinuousClock.now < deadline {
            drain()
            do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
        }
        let timedOut = ContinuousClock.now >= deadline
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        await Task.detached { exit.wait() }.value
        drain()
        try Task.checkCancellation()
        return Result(status: process.terminationStatus,
                      output: String(data: bytes, encoding: .utf8) ?? "invalid-utf8",
                      timedOut: timedOut)
    }
}
