import Darwin
import Foundation
import OSLog

@MainActor
protocol SoloistChild: AnyObject {
    var pid: Int32 { get }
    func stop()
}

@MainActor
protocol SoloistLauncher: AnyObject {
    func launch(_ executable: URL, arguments: [String],
                onExit: @escaping @MainActor (Int32) -> Void) throws -> any SoloistChild
}

@MainActor
final class LiveSoloistLauncher: SoloistLauncher {
    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void = { line in
        Logger(subsystem: NotchcastIdentity.current.bundleID, category: "Soloist")
            .info("\(line, privacy: .public)")
    }) {
        self.log = log
    }

    func launch(_ executable: URL, arguments: [String],
                onExit: @escaping @MainActor (Int32) -> Void) throws -> any SoloistChild {
        try LiveChild(executable: executable, arguments: arguments, log: log, onExit: onExit)
    }

    private final class LiveChild: SoloistChild {
        private let process: Process
        private let handle: FileHandle
        private var exitTask: Task<Void, Never>?
        private var stopping = false

        var pid: Int32 { process.processIdentifier }

        init(executable: URL, arguments: [String], log: @escaping @Sendable (String) -> Void,
             onExit: @escaping @MainActor (Int32) -> Void) throws {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ExecutableLocator.environment(
                running: executable, adding: ["LANG": "en_US.UTF-8"], inherited: [:])
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let output = SoloistOutput(arguments: arguments, log: log)
            let handle = pipe.fileHandleForReading
            self.process = process
            self.handle = handle
            let exit: ProcessExit
            do { exit = try process.runObservingExit() } catch {
                throw SoloistFailure.process
            }
            try? pipe.fileHandleForWriting.close()
            exitTask = Task {
                await Self.drain(handle, output: output, exit: exit)
                guard !Task.isCancelled else { return }
                onExit(process.terminationStatus)
            }
        }

        @concurrent
        private static func drain(_ handle: FileHandle, output: SoloistOutput, exit: ProcessExit) async {
            do {
                while let data = try handle.read(upToCount: 65_536), !data.isEmpty { output.consume(data) }
            } catch {}
            output.finish()
            exit.wait()
        }

        func stop() {
            guard !stopping else { return }
            stopping = true
            guard process.isRunning else { return }
            process.terminate()
            let process = process
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }

        isolated deinit {
            exitTask?.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? handle.close()
        }
    }
}
