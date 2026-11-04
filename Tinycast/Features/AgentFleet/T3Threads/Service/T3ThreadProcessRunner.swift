import Foundation
import Synchronization

enum T3ThreadProcessRunner {
    enum Failure: LocalizedError, Equatable {
        case missingBinary, exit(Int32)

        var errorDescription: String? {
            switch self {
            case .missingBinary: String(localized: "Install the T3 command line tool to read threads.")
            case .exit: String(localized: "T3 could not read threads.")
            }
        }
    }

    @concurrent
    static func run() async throws -> Data {
        let process = Process()
        let state = Mutex(false)
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["t3", "thread", "list", "--json"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            let exit = try state.withLock { cancelled in
                if cancelled { throw CancellationError() }
                return try process.runObservingExit()
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            exit.wait()
            try Task.checkCancellation()
            if process.terminationStatus == 127 { throw Failure.missingBinary }
            guard process.terminationStatus == 0 else { throw Failure.exit(process.terminationStatus) }
            return data
        } onCancel: {
            state.withLock { cancelled in
                cancelled = true
                if process.isRunning { process.terminate() }
            }
        }
    }
}
