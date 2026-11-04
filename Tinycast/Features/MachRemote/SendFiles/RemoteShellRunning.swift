import Foundation

@MainActor
protocol RemoteShellRunning {
    var sshAlias: String { get }
    // Implementations stream both pipes, terminate on cancellation, and drain before returning.
    func run(_ executable: String, arguments: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> SendFilesProcessResult
}

struct SendFilesProcessResult: Sendable {
    let status: Int32
    let output: String
}
