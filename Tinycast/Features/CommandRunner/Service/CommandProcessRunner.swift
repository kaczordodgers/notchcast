import Darwin
import Foundation

enum CommandProcessRunner {
    @concurrent
    static func run(_ request: CatalogShellCommandRunner.Request) async throws
        -> CatalogShellCommandRunner.Result
    {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appending(path: "stdout")
        let errorURL = directory.appending(path: "stderr")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? errors.close()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory.map { URL(fileURLWithPath: $0) }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let exit = try process.runObservingExit()
        var cancelled = false
        while process.isRunning {
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                cancelled = true
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                break
            }
        }
        exit.wait()
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
        return try CatalogShellCommandRunner.Result(
            exitStatus: process.terminationStatus,
            standardOutput: read(outputURL), standardError: read(errorURL))
    }

    private static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 1_048_576) ?? Data()
    }
}
