import Foundation

@MainActor
struct MachRemoteShell {
    let ssh: MachSSH

    func run(_ executable: String, arguments: [String]) async throws -> MachSSH.Result {
        if executable == "/usr/bin/ssh", let command = arguments.last {
            var options = Array(arguments.dropLast(2))
            if options.last == "--" { options.removeLast() }
            return try await ssh.run(command, options: options)
        }
        var arguments = arguments
        if executable == "/usr/bin/rsync", let index = arguments.firstIndex(of: "-e"),
           arguments.indices.contains(index + 1) {
            let callerOptions = arguments[index + 1].drop { $0 != " " }
            arguments[index + 1] = MachSSH.quote("/usr/bin/ssh") + callerOptions + " "
                + MachSSH.options.map(MachSSH.quote).joined(separator: " ")
        }
        return try await ssh.runner(executable, arguments)
    }
}

@MainActor
struct MachSendFilesRunner: RemoteShellRunning {
    let shell: MachRemoteShell
    var sshAlias: String { shell.ssh.address }

    func run(_ executable: String, arguments: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> SendFilesProcessResult {
        let result = try await shell.run(executable, arguments: arguments)
        output(result.output)
        return SendFilesProcessResult(status: result.status, output: result.output)
    }
}

@MainActor
struct MachUpdateRunner: UpdateRemoteShellRunning {
    let shell: MachRemoteShell
    var sshAlias: String { shell.ssh.address }

    func run(_ executable: String, arguments: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> UpdateRemoteProcessResult {
        let result = try await shell.run(executable, arguments: arguments)
        for line in result.output.split(separator: "\n") { output(String(line)) }
        return UpdateRemoteProcessResult(status: result.status, output: result.output)
    }
}
