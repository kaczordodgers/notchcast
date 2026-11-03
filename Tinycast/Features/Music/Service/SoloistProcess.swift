import Darwin
import Foundation

enum SoloistProcess {
    struct Output: Sendable {
        let status: Int32
        let text: String
    }

    @concurrent
    static func run(_ executable: URL, arguments: [String], timeout: Duration = .seconds(10),
                    readPipe: @escaping @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int = {
                        Darwin.read($0, $1, $2)
                    }) async throws -> Output {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw SoloistFailure.process }
        let exit = try process.runObservingExit()
        try? pipe.fileHandleForWriting.close()
        let deadline = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        defer { deadline.cancel() }
        let result = try await withTaskCancellationHandler {
            try await read(process, pipe: pipe, exit: exit, readPipe: readPipe)
        } onCancel: {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try Task.checkCancellation()
        guard let result else { throw SoloistFailure.process }
        return result
    }

    @concurrent
    private static func read(_ process: Process, pipe: Pipe, exit: ProcessExit,
                             readPipe: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int) async throws -> Output? {
        defer { try? pipe.fileHandleForReading.close() }
        var data = Data()
        var refused = false
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var exited = false
        while true {
            let count = readPipe(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                if data.count + count > 1 << 20 { refused = true }
                if !refused { data.append(contentsOf: buffer.prefix(count)) }
                if refused {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    exit.wait()
                    return nil
                }
                continue
            }
            if exited { break }
            if !process.isRunning { exited = true; continue }
            if count < 0, errno != EAGAIN, errno != EINTR {
                refused = true
                kill(process.processIdentifier, SIGKILL)
            }
            do { try await Task.sleep(for: .milliseconds(10)) } catch {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                exit.wait()
                throw error
            }
        }
        exit.wait()
        guard !refused else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Output(status: process.terminationStatus, text: text)
    }
}
