import Darwin
import Foundation

nonisolated enum ArchiveProcess {
    struct Result: Sendable {
        let status: Int32
        let listing: ArchiveListing?
    }

    @concurrent static func run(
        tool: URL, arguments: [String], captureListing: Bool = false,
        progress: @escaping @Sendable () async -> Void = {}
    ) async throws -> Result {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { throw ArchiveFailure.filesystem("pipe") }
        try Task.checkCancellation()
        let exit = try process.runObservingExit()
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        var listing = captureListing ? ArchiveListing() : nil
        var failure: (any Error)?
        var stopped: ContinuousClock.Instant?
        var buffer = [UInt8](repeating: 0, count: 8192)
        var ended = false
        var updated = ContinuousClock.now
        while process.isRunning || !ended {
            if Task.isCancelled || failure != nil {
                if stopped == nil {
                    stopped = .now
                    if process.isRunning { signalGroup(process, SIGINT) }
                } else if let stopped, process.isRunning {
                    if stopped.duration(to: .now) > .seconds(3) {
                        signalGroup(process, SIGKILL)
                    } else if stopped.duration(to: .now) > .seconds(1) {
                        signalGroup(process, SIGTERM)
                    }
                }
            }
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0, failure == nil {
                do { try listing?.feed(Data(buffer.prefix(count))) } catch { failure = error }
            } else if count == 0 {
                ended = true
            } else if count < 0, errno != EAGAIN, errno != EINTR {
                failure = ArchiveFailure.filesystem("read")
                ended = true
            }
            if count <= 0 {
                if updated.duration(to: .now) >= .milliseconds(250) {
                    await progress()
                    updated = .now
                }
                var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                _ = poll(&event, 1, 250)
            }
        }
        exit.wait()
        if Task.isCancelled, process.terminationStatus != 0 { throw CancellationError() }
        if let failure { throw failure }
        if captureListing, process.terminationStatus == 0 { try listing?.finish() }
        return Result(status: process.terminationStatus, listing: listing)
    }

    static func validate(_ status: Int32) throws {
        switch status {
        case 0: return
        case 3: throw ArchiveFailure.insufficientSpace
        case 4: throw ArchiveFailure.damagedArchive
        case 5: throw ArchiveFailure.passwordRequired
        default: throw ArchiveFailure.toolFailed(status)
        }
    }

    private static func signalGroup(_ process: Process, _ signal: Int32) {
        let identifier = process.processIdentifier
        let target = getpgid(identifier) == identifier ? -identifier : identifier
        kill(target, signal)
    }
}
