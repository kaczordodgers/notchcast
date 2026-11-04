import Foundation

@MainActor
protocol UpdateRemoteShellRunning {
    var sshAlias: String { get }
    // The transport drains both pipes and terminates its child when the caller cancels.
    func run(_ executable: String, arguments: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> UpdateRemoteProcessResult
}

struct UpdateRemoteProcessResult: Sendable {
    let status: Int32
    let output: String
}
