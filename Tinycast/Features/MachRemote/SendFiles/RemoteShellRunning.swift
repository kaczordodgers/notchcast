import Foundation

@MainActor
protocol RemoteShellRunning {
    var sshAlias: String { get }
    // Output is stdout delivered after exit; stderr is discarded.
    func ssh(command: String, options: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> MachSSH.Result
    func rsync(source: URL, destination: String, output: @escaping @MainActor (String) -> Void)
        async throws -> MachSSH.Result
}
