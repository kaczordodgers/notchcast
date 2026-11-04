import Foundation
import Synchronization
import Darwin

struct MachineBackupRunner: MachineBackupTooling {
    private static let queue = DispatchQueue(label: "app.notchcast.machine-backup", attributes: .concurrent)
    private static let outputLimit = 16 * 1024 * 1024

    func run(_ request: MachineBackupRequest) async throws -> Data {
        let session = Session()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    do {
                        continuation.resume(returning: try Self.execute(request, session: session))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            session.cancel()
        }
    }

    static func reserveRestoreTarget(_ target: URL, home: URL) throws {
        try MachineBackupPolicy.validateTarget(target, home: home)
        let resolvedHome = home.resolvingSymlinksInPath().standardizedFileURL
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        guard parent == resolvedHome.appendingPathComponent("Downloads", isDirectory: true) else {
            throw MachineBackupFailure.unsafeTarget
        }
        let resolvedTarget = parent.appendingPathComponent(target.lastPathComponent, isDirectory: true)
        try MachineBackupPolicy.validateTarget(resolvedTarget, home: resolvedHome)
        let result = target.withUnsafeFileSystemRepresentation { path in
            path.map { mkdir($0, 0o700) } ?? -1
        }
        guard result == 0 else {
            if errno == EEXIST { throw MachineBackupFailure.targetExists }
            throw MachineBackupFailure.unsafeTarget
        }
    }

    private static func execute(_ request: MachineBackupRequest, session: Session) throws -> Data {
        try session.checkCancellation()
        if let target = request.restoreTarget {
            guard let home = request.homeDirectory else { throw MachineBackupFailure.configuration }
            try reserveRestoreTarget(target, home: home)
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "LANG": "en_US.UTF-8"]
            .merging(request.environment) { _, value in value }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exit = try session.launch(process)
        queue.asyncAfter(deadline: .now() + .seconds(300)) { session.cancel() }
        defer {
            output.fileHandleForReading.closeFile()
            session.finish()
        }
        var result = Data()
        do {
            while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                guard result.count + chunk.count <= outputLimit else { throw MachineBackupFailure.outputLimit }
                result.append(chunk)
                try session.checkCancellation()
            }
        } catch {
            session.cancel()
            exit.wait()
            throw error
        }
        exit.wait()
        try session.checkCancellation()
        guard process.terminationStatus == 0 else { throw MachineBackupFailure.toolFailed(process.terminationStatus) }
        return result
    }

    private final class Session: Sendable {
        private struct State {
            var process: Process?
            var cancelled = false
        }
        private let state = Mutex(State())

        func launch(_ process: Process) throws -> ProcessExit {
            try state.withLock {
                guard !$0.cancelled else { throw CancellationError() }
                let exit = try process.runObservingExit()
                $0.process = process
                return exit
            }
        }

        func cancel() {
            state.withLock {
                $0.cancelled = true
                if let process = $0.process, process.isRunning { process.interrupt() }
            }
            MachineBackupRunner.queue.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
                state.withLock {
                    if let process = $0.process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        func finish() { state.withLock { $0.process = nil } }

        func checkCancellation() throws {
            try state.withLock { if $0.cancelled { throw CancellationError() } }
        }
    }
}
