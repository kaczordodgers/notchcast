import Foundation
import Darwin

@MainActor
protocol MacUpdateProcessRunning {
    func run(_ command: MacUpdateCommand) async throws -> MacUpdateRunner.Result
}

@MainActor
struct MacUpdateRunner: MacUpdateProcessRunning {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var timedOut = false
    }

    func run(_ command: MacUpdateCommand) async throws -> Result {
        precondition(command.path.hasPrefix("/"))
        try Task.checkCancellation()
        let pipe = Pipe()
        var bytes = Data()
        let environment = ExecutableLocator.environment(running: URL(filePath: command.path))
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw POSIXError(.EIO)
        }
        func drain() {
            var buffer = [UInt8](repeating: 0, count: 8192)
            for _ in 0..<16 {
                let count = read(descriptor, &buffer, buffer.count)
                guard count > 0 else { return }
                bytes.append(contentsOf: buffer.prefix(count))
                if bytes.count > 65536 { bytes.removeFirst(bytes.count - 65536) }
            }
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        for target in [STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_adddup2(&actions, pipe.fileHandleForWriting.fileDescriptor, target)
        }
        posix_spawn_file_actions_addclose(&actions, descriptor)
        let arguments = ([command.path] + command.arguments).map { strdup($0) }
        let variables = environment.map { strdup("\($0.key)=\($0.value)") }
        defer {
            arguments.forEach { free($0) }
            variables.forEach { free($0) }
        }
        var pid: pid_t = 0
        let error = (arguments + [nil]).withUnsafeBufferPointer { argv in
            (variables + [nil]).withUnsafeBufferPointer { envp in
                posix_spawn(&pid, command.path, &actions, &attributes,
                            UnsafeMutablePointer(mutating: argv.baseAddress!),
                            UnsafeMutablePointer(mutating: envp.baseAddress!))
            }
        }
        guard error == 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
        pipe.fileHandleForWriting.closeFile()
        defer { pipe.fileHandleForReading.closeFile() }
        var status: Int32 = 0
        var reaped = false
        let deadline = ContinuousClock.now + command.timeout
        while !Task.isCancelled && ContinuousClock.now < deadline {
            drain()
            if waitpid(pid, &status, WNOHANG) == pid { reaped = true; break }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
        }
        let timedOut = ContinuousClock.now >= deadline
        if !reaped {
            kill(-pid, SIGTERM)
            await Task.detached { try? await Task.sleep(for: .milliseconds(250)) }.value
            kill(-pid, SIGKILL)
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
        drain()
        try Task.checkCancellation()
        let signal = status & 0x7f
        return Result(status: signal == 0 ? (status >> 8) & 255 : 128 + signal,
                      output: String(data: bytes, encoding: .utf8) ?? "invalid-utf8",
                      timedOut: timedOut)
    }
}
