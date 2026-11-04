import Darwin
import Foundation

enum CleanProcessRunner {
    struct Result: Sendable {
        let code: Int32
        let output: String
        let error: String
    }

    static func execute(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> Result {
        try Task.checkCancellation()
        let directory = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager().removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        let errors = directory.appendingPathComponent("errors")
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addopen(&actions, 2, errors.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        let argv = ([executable.path] + arguments).map { strdup($0) }
        let environment = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "GIT_TERMINAL_PROMPT=0"].map {
            $0.withCString { strdup($0) }
        }
        defer { for value in argv + environment { free(value) } }
        var pid: pid_t = 0
        let result = (argv + [nil]).withUnsafeBufferPointer { args in
            (environment + [nil]).withUnsafeBufferPointer { env in
                posix_spawn(&pid, executable.path, &actions, &attributes,
                    UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        var status: Int32 = 0
        while true {
            if Task.isCancelled || ContinuousClock.now >= deadline {
                kill(-pid, SIGTERM)
                let grace = ContinuousClock.now.advanced(by: .milliseconds(100))
                while ContinuousClock.now < grace {
                    await pause()
                }
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                try Task.checkCancellation()
                throw POSIXError(.ETIMEDOUT)
            }
            if waitpid(pid, &status, WNOHANG) == pid { break }
            await pause()
        }
        func text(_ url: URL) throws -> String {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 1_048_577) ?? Data()
            guard data.count <= 1_048_576, let value = String(data: data, encoding: .utf8)
            else { throw POSIXError(.EFBIG) }
            return value
        }
        return try Result(code: status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f),
            output: text(output), error: text(errors))
    }

    private static func pause() async {
        await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
    }
}
