import Foundation

@MainActor
struct MachRemoteShell: RemoteShellRunning {
    let ssh: MachSSH
    var sshAlias: String { ssh.address }

    func ssh(command: String, options: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> MachSSH.Result {
        try await streaming(to: output) { [ssh] in try await ssh.run(command, options: options, onLine: $0) }
    }

    func rsync(source: URL, destination: String, output: @escaping @MainActor (String) -> Void)
        async throws -> MachSSH.Result {
        guard MachSSH.isValid(ssh.address) else { throw MachSSH.ConfigurationError.address }
        let remoteShell = (["/usr/bin/ssh"] + MachSSH.options).map(MachSSH.quote).joined(separator: " ")
        let arguments = [
            "-a", "--safe-links", "--progress", "--timeout=30", "-e", remoteShell,
            "--", source.path, ssh.address + ":" + MachSSH.quote(destination),
        ]
        return try await streaming(to: output) { [ssh] in try await ssh.runner("/usr/bin/rsync", arguments, $0) }
    }

    // The runner splits rsync's `\r` progress updates into records; each gets its `\n` back.
    private func streaming(to output: @escaping @MainActor (String) -> Void,
                           _ run: @escaping @Sendable (@escaping MachSSH.LineSink) async throws -> MachSSH.Result)
        async throws -> MachSSH.Result {
        let (records, sink) = AsyncStream.makeStream(of: String.self)
        async let result: MachSSH.Result = {
            defer { sink.finish() }
            return try await run { sink.yield($0) }
        }()
        for await record in records { output(record + "\n") }
        return try await result
    }
}
