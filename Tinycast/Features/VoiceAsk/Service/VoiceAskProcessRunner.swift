import Foundation

@MainActor
enum VoiceAskProcessRunner {
    static func run(_ executable: URL, arguments: [String], input: Data,
                    timeout: Duration = .seconds(120)) async throws -> VoiceAskCLITransport.Output {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let exit = try process.runObservingExit()
        let writer = Task.detached {
            defer { try? stdin.fileHandleForWriting.close() }
            try stdin.fileHandleForWriting.write(contentsOf: input)
        }
        let reader = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        var timedOut = false
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            timedOut = true
            if process.isRunning { process.terminate() }
        }
        await withTaskCancellationHandler {
            await Task.detached { exit.wait() }.value
        } onCancel: {
            Task { @MainActor in if process.isRunning { process.terminate() } }
        }
        timer.cancel()
        let data = await reader.value
        let written = await writer.result
        try Task.checkCancellation()
        if timedOut { throw VoiceAskCLIError.timeout }
        try written.get()
        return .init(status: process.terminationStatus, stdout: data)
    }
}
