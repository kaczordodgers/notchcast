import Foundation
import Synchronization

nonisolated enum ArchiveProcess {
    struct Result: Sendable {
        var status: Int32 = 0
        var listing: ArchiveListing?
        var output = Data()
        var outputBytes: Int64 = 0
    }

    @concurrent static func run(
        tool: URL, arguments: [String], captureListing: Bool = false, captureOutput: Bool = false,
        outputFile: URL? = nil, maximumOutputBytes: Int64? = nil,
        environment: [String: String]? = nil,
        progress: @escaping @Sendable () async -> Void = {}
    ) async throws -> Result {
        try Task.checkCancellation()
        let destination: FileHandle?
        if let outputFile {
            try Data().write(to: outputFile, options: .withoutOverwriting)
            destination = try FileHandle(forWritingTo: outputFile)
        } else {
            destination = nil
        }
        defer { try? destination?.close() }
        let result = Mutex(Result(listing: captureListing ? ArchiveListing() : nil))
        var request = ProcessRunner.Request(executable: tool, arguments: arguments,
            environment: environment ?? ExecutableLocator.environment(running: tool))
        request.stopsGroup = true
        request.groupCleanup = .drainThenKill
        request.stopLadder = .interrupting(kill: .seconds(3))
        request.onData = { data in
            try result.withLock { result in
                let count = data.count
                if let maximumOutputBytes, Int64(count) > maximumOutputBytes - result.outputBytes {
                    throw ArchiveFailure.expansionLimit
                }
                result.outputBytes += Int64(count)
                if captureOutput {
                    guard result.output.count + count <= 16_000_000 else { throw ArchiveFailure.invalidListing }
                    result.output.append(data)
                }
                try result.listing?.feed(data)
                if let outputFile {
                    try ArchiveFallbackSpace.check(outputFile.deletingLastPathComponent(), additionalBytes: Int64(count))
                }
                try destination?.write(contentsOf: data)
            }
        }
        let ticker = Task.detached {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                guard !Task.isCancelled else { break }
                await progress()
            }
        }
        let output: ProcessRunner.Output
        do { output = try await ProcessRunner.run(request) } catch {
            ticker.cancel()
            await ticker.value
            try Task.checkCancellation()
            throw error
        }
        ticker.cancel()
        await ticker.value
        return try result.withLock { result in
            result.status = output.signaled ? 128 + output.status : output.status
            if captureListing, result.status == 0 { try result.listing?.finish() }
            return result
        }
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
}
