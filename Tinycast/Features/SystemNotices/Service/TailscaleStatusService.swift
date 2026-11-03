import Darwin
import Foundation
import Synchronization

struct TailscaleStatusService: Sendable {
    var executable: URL?
    var timeout: Duration = .seconds(2)
    private static let maximumOutput = 256 * 1024

    @concurrent
    func read() async -> TailscaleState {
        let candidates = [
            "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]
        let executable = executable ?? candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map { URL(filePath: $0) }
        guard let executable, !Task.isCancelled else { return .unavailable }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["status", "--json", "--peers=false"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exited = Mutex(false)
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { return .unavailable }
        defer {
            pipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
        }
        do { try process.runObservingExit { exited.withLock { $0 = true } } } catch { return .unavailable }
        pipe.fileHandleForWriting.closeFile()
        let deadline = ContinuousClock.now + timeout
        var output = Data()
        var failed = false
        var killed = false
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                if output.count + count <= Self.maximumOutput {
                    output.append(contentsOf: buffer.prefix(count))
                } else {
                    failed = true
                }
            } else if count < 0 && errno != EAGAIN && errno != EINTR {
                failed = true
            }
            let finished = exited.withLock { $0 }
            if finished && count <= 0 { break }
            if Task.isCancelled || ContinuousClock.now >= deadline || failed {
                failed = true
                if !finished, !killed {
                    kill(process.processIdentifier, SIGKILL)
                    killed = true
                }
            }
            if count <= 0 {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { failed = true; await Task.yield() }
            }
        }
        guard !failed, !Task.isCancelled, process.terminationStatus == 0 else { return .unavailable }
        return TailscaleState.parse(output)
    }
}

private extension Process {
    func runObservingExit(_ onExit: @escaping @Sendable () -> Void) throws {
        terminationHandler = { _ in onExit() }
        try run()
    }
}
