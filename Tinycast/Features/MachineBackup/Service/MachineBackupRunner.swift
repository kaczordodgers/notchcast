import Darwin
import Foundation

struct MachineBackupRunner: MachineBackupTooling {
    private static let outputLimit = 16 * 1024 * 1024

    @concurrent
    func run(_ request: MachineBackupRequest) async throws -> Data {
        try Task.checkCancellation()
        if let target = request.restoreTarget {
            guard let home = request.homeDirectory else { throw MachineBackupFailure.configuration }
            try Self.reserveRestoreTarget(target, home: home)
        }
        let run = ProcessRunner.Request(
            executable: request.executable, arguments: request.arguments,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "LANG": "en_US.UTF-8"]
                .merging(request.environment) { _, value in value },
            timeout: .seconds(300), outputLimit: Self.outputLimit, stopSignal: SIGINT)
        let output: ProcessRunner.Output
        do { output = try await ProcessRunner.run(run) } catch ProcessRunner.Failure.timedOut {
            throw CancellationError()
        } catch ProcessRunner.Failure.outputLimit {
            throw MachineBackupFailure.outputLimit
        }
        guard output.status == 0 else { throw MachineBackupFailure.toolFailed(output.status) }
        return output.stdout
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
}
