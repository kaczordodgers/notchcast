import Foundation

@MainActor
struct MachRemoteShell: RemoteShellRunning {
    let ssh: MachSSH
    var sshAlias: String { ssh.address }

    func ssh(command: String, options: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> MachSSH.Result {
        let result = try await ssh.run(command, options: options)
        output(result.output)
        return result
    }

    func rsync(source: URL, destination: String, output: @escaping @MainActor (String) -> Void)
        async throws -> MachSSH.Result {
        guard MachSSH.isValid(ssh.address) else { throw MachSSH.ConfigurationError.address }
        let remoteShell = (["/usr/bin/ssh"] + MachSSH.options).map(MachSSH.quote).joined(separator: " ")
        let result = try await ssh.runner("/usr/bin/rsync", [
            "-a", "--safe-links", "--progress", "--timeout=30", "-e", remoteShell,
            "--", source.path, ssh.address + ":" + MachSSH.quote(destination),
        ])
        output(result.output)
        return result
    }
}
