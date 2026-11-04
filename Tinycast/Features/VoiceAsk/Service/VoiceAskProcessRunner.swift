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
        for handle in [stdin.fileHandleForWriting, stdout.fileHandleForReading, stderr.fileHandleForReading] {
            let flags = fcntl(handle.fileDescriptor, F_GETFL)
            guard flags >= 0, fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        let exit = try process.runObservingExit()
        let writer = Task.detached { @Sendable in
            defer { try? stdin.fileHandleForWriting.close() }
            var offset = 0
            while offset < input.count {
                try Task.checkCancellation()
                let count = input.withUnsafeBytes {
                    Darwin.write(stdin.fileHandleForWriting.fileDescriptor,
                                 $0.baseAddress!.advanced(by: offset), input.count - offset)
                }
                if count > 0 { offset += count } else if errno != EAGAIN && errno != EINTR {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                } else { try await Task.sleep(for: .milliseconds(10)) }
            }
        }
        let reader = Task.detached { @Sendable in
            try await read(stdout.fileHandleForReading, limit: Int.max)
        }
        let errorReader = Task.detached { @Sendable in
            try await read(stderr.fileHandleForReading, limit: 500)
        }
        var timedOut = false
        var grace: Task<Void, Never>?
        let stop: @MainActor @Sendable () -> Void = {
            guard grace == nil else { return }
            if process.isRunning { process.terminate() }
            grace = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                writer.cancel()
                reader.cancel()
                errorReader.cancel()
            }
        }
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled else { return }
            timedOut = true
            stop()
        }
        return try await withTaskCancellationHandler {
            defer { timer.cancel(); grace?.cancel() }
            await withCheckedContinuation { continuation in
                Thread.detachNewThread { @Sendable in
                    exit.wait()
                    continuation.resume()
                }
            }
            let data = await reader.result
            let diagnostic = await errorReader.result
            let written = await writer.result
            try Task.checkCancellation()
            if timedOut { throw VoiceAskCLIError.timeout }
            try written.get()
            return try .init(status: process.terminationStatus, stdout: data.get(), stderr: diagnostic.get())
        } onCancel: {
            Task { @MainActor in stop() }
        }
    }

    nonisolated private static func read(_ handle: FileHandle, limit: Int) async throws -> Data {
        defer { try? handle.close() }
        var captured = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count == 0 { return captured }
            if count > 0 {
                captured.append(contentsOf: buffer.prefix(min(count, limit - captured.count)))
            } else if errno != EAGAIN && errno != EINTR {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            } else { try await Task.sleep(for: .milliseconds(10)) }
        }
    }
}
