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
        let name = executable.lastPathComponent
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw failure(name, "fcntl", errno) }
        let exit: ProcessExit
        do { exit = try process.runObservingExit() } catch {
            throw SoloistFailure.process.detail("\(name): \(SoloistFailure.describe(error))")
        }
        try? pipe.fileHandleForWriting.close()
        let deadline = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        defer { deadline.cancel() }
        let result = try await withTaskCancellationHandler {
            try await read(process, name: name, pipe: pipe, exit: exit, readPipe: readPipe)
        } onCancel: {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try Task.checkCancellation()
        return result
    }

    @concurrent
    private static func read(_ process: Process, name: String, pipe: Pipe, exit: ProcessExit,
                             readPipe: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int) async throws -> Output {
        defer { try? pipe.fileHandleForReading.close() }
        var data = Data()
        var refusal: SoloistFailure?
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var exited = false
        while true {
            let count = readPipe(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
            // Read now: any later call, `isRunning` included, may overwrite errno.
            let error = count < 0 ? errno : 0
            if count > 0 {
                guard data.count + count <= 1 << 20 else {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    exit.wait()
                    throw SoloistFailure.process.detail("\(name): output over 1 MB")
                }
                data.append(contentsOf: buffer.prefix(count))
                continue
            }
            if exited { break }
            if !process.isRunning { exited = true; continue }
            if count < 0, error != EAGAIN, error != EINTR, refusal == nil {
                refusal = failure(name, "read", error)
                kill(process.processIdentifier, SIGKILL)
            }
            do { try await Task.sleep(for: .milliseconds(10)) } catch {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                exit.wait()
                throw error
            }
        }
        exit.wait()
        if let refusal { throw refusal }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SoloistFailure.process.detail("\(name): output isn’t UTF-8 text")
        }
        return Output(status: process.terminationStatus, text: text)
    }

    private static func failure(_ name: String, _ call: String, _ code: Int32) -> SoloistFailure {
        .process.detail("\(name): \(call): \(String(cString: strerror(code))) (errno \(code))")
    }
}
