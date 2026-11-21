import Foundation
import Synchronization

/// Runs one tool to its exit; a cancel sends SIGINT, which HatchZip answers by saving its progress.
nonisolated enum ArchiveProcess {
    private struct Launch {
        var process: Process?
        var cancelled = false
    }

    static func run(
        _ executable: URL, _ arguments: [String], environment extra: [String: String] = [:]
    ) async throws -> ArchiveProcessResult {
        let launch = Mutex(Launch())
        let environment = ExecutableLocator.environment(running: executable, adding: extra)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Blocking reads and the exit wait stay off the cooperative pool.
                DispatchQueue.global().async {
                    let output = Pipe()
                    let errors = Pipe()
                    let exit: ProcessExit
                    do {
                        exit = try launch.withLock { launch in
                            guard !launch.cancelled else { throw CancellationError() }
                            let process = Process()
                            process.executableURL = executable
                            process.arguments = arguments
                            process.environment = environment
                            process.standardInput = FileHandle.nullDevice
                            process.standardOutput = output
                            process.standardError = errors
                            let exit = try process.runObservingExit()
                            launch.process = process
                            return exit
                        }
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    let said = Mutex(Data())
                    let group = DispatchGroup()
                    DispatchQueue.global().async(group: group) {
                        let data = errors.fileHandleForReading.readDataToEndOfFile()
                        said.withLock { $0 = data }
                    }
                    let printed = output.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    exit.wait()
                    let (status, cancelled) = launch.withLock { launch in
                        defer { launch.process = nil }
                        return (launch.process?.terminationStatus ?? -1, launch.cancelled)
                    }
                    if cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: ArchiveProcessResult(
                            status: status, output: String(decoding: printed, as: UTF8.self),
                            errors: String(decoding: said.withLock { $0 }, as: UTF8.self)))
                    }
                }
            }
        } onCancel: {
            launch.withLock { launch in
                launch.cancelled = true
                if let process = launch.process, process.isRunning { process.interrupt() }
            }
        }
    }
}
