import Foundation
import Darwin

@MainActor
enum VoiceAskProcessRunner {
    static func run(_ executable: URL, arguments: [String], input: Data,
                    timeout: Duration = .seconds(120)) async throws -> VoiceAskCLITransport.Output {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ExecutableLocator.environment(running: executable)
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let exit = DispatchSemaphore(value: 0)
        let waitForExit: @Sendable () -> Void = { exit.wait() }
        process.terminationHandler = { @Sendable _ in exit.signal() }
        try process.run()
        let writer = Task.detached { @Sendable in
            defer { try? stdin.fileHandleForWriting.close() }
            try stdin.fileHandleForWriting.write(contentsOf: input)
        }
        let reader = Task.detached { @Sendable in stdout.fileHandleForReading.readDataToEndOfFile() }
        let errorReader = Task.detached { @Sendable in
            var captured = Data()
            while let chunk = try stderr.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                captured.append(chunk.prefix(max(0, 500 - captured.count)))
            }
            return captured
        }
        var timedOut = false
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            timedOut = true
            if process.isRunning { process.terminate() }
        }
        await withTaskCancellationHandler {
            await Task.detached { waitForExit() }.value
        } onCancel: {
            Task { @MainActor in if process.isRunning { process.terminate() } }
        }
        timer.cancel()
        let data = await reader.value
        let diagnostic = try await errorReader.value
        let written = await writer.result
        try Task.checkCancellation()
        if timedOut { throw VoiceAskCLIError.timeout }
        try written.get()
        return .init(status: process.terminationStatus, stdout: data, stderr: diagnostic)
    }
}
