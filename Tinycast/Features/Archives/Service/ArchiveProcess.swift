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
        let pipe = Pipe()
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { throw ArchiveFailure.filesystem("pipe") }
        try Task.checkCancellation()
        let identifier = try launch(tool: tool, arguments: arguments, pipe: pipe)
        var status: Int32 = 0
        defer {
            kill(-identifier, SIGKILL)
            while waitpid(identifier, &status, 0) < 0 && errno == EINTR {}
        }
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        var listing = captureListing ? ArchiveListing() : nil
        var failure: (any Error)?
        var stopped: ContinuousClock.Instant?
        var buffer = [UInt8](repeating: 0, count: 8192)
        var ended = false
        var updated = ContinuousClock.now
        var running = true
        var terminationStatus: Int32 = 0
        while running || !ended {
            var information = siginfo_t()
            if waitid(P_PID, id_t(identifier), &information, WEXITED | WNOHANG | WNOWAIT) == 0 {
                running = information.si_pid == 0
                if !running {
                    terminationStatus = information.si_code == CLD_EXITED
                        ? information.si_status : 128 + information.si_status
                }
            }
            if Task.isCancelled || failure != nil {
                if stopped == nil {
                    stopped = .now
                    kill(-identifier, SIGINT)
                } else if let stopped {
                    if stopped.duration(to: .now) > .seconds(3) {
                        kill(-identifier, SIGKILL)
                        ended = true
                        if !running { break }
                    } else if stopped.duration(to: .now) > .seconds(1) {
                        kill(-identifier, SIGTERM)
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
        try Task.checkCancellation()
        if let failure { throw failure }
        if captureListing, terminationStatus == 0 { try listing?.finish() }
        return Result(status: terminationStatus, listing: listing)
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

    private static func launch(tool: URL, arguments: [String], pipe: Pipe) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        let argv = ([tool.path] + arguments).map { strdup($0) } + [nil]
        let envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var identifier: pid_t = 0
        let error = argv.withUnsafeBufferPointer { argv in
            envp.withUnsafeBufferPointer { envp in
                posix_spawn(&identifier, tool.path, &actions, &attributes,
                    UnsafeMutablePointer(mutating: argv.baseAddress!),
                    UnsafeMutablePointer(mutating: envp.baseAddress!))
            }
        }
        guard error == 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
        return identifier
    }
}
