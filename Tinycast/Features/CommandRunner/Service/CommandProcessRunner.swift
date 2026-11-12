import AppKit
import Foundation
import Synchronization

enum CommandProcessRunner {
    @concurrent
    static func run(_ request: CatalogShellCommandRunner.Request) async throws
        -> CatalogShellCommandRunner.Result
    {
        let state = Mutex<(terminated: Bool, running: ProcessRunner.Running?)>((false, nil))
        let center = NotificationCenter.default
        let token = NotificationToken(center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in state.withLock { $0.terminated = true; $0.running?.terminate() } }, center: center)
        defer { withExtendedLifetime(token) {} }
        do {
            try Task.checkCancellation()
            let running = try state.withLock { state in
                guard !state.terminated else { throw CancellationError() }
                let running = try ProcessRunner.start(.init(
                    executable: URL(fileURLWithPath: request.executable), arguments: request.arguments,
                    environment: DownloadToolLookup().environment,
                    directory: request.workingDirectory.map { URL(fileURLWithPath: $0) },
                    stderr: .capture(limit: 65_536), timeout: request.timeout,
                    stopLadder: .terminating(grace: .milliseconds(250)), stopsGroup: true,
                    outputTail: 65_536))
                state.running = running
                return running
            }
            defer { state.withLock { $0.running = nil } }
            let result = try await running.output()
            return CatalogShellCommandRunner.Result(exitStatus: result.signaled ? 128 + result.status : result.status,
                standardOutput: tail(result.stdout), standardError: tail(result.stderr))
        } catch ProcessRunner.Failure.timedOut {
            return CatalogShellCommandRunner.Result(exitStatus: 143, standardOutput: Data(), standardError: Data())
        }
    }

    private static func tail(_ data: Data) -> Data {
        let bytes = data.suffix(65_536).drop(while: { $0 & 0xC0 == 0x80 })
        return Data((String(bytes: bytes, encoding: .utf8) ?? "").utf8)
    }
}
