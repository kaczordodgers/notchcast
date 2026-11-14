import Foundation

enum MachSSHProcessRunner {
    @concurrent static func run(_ executable: String, _ arguments: [String],
                                onLine: MachSSH.LineSink? = nil) async throws -> MachSSH.Result {
        let output = try await ProcessRunner.run(.init(executable: URL(fileURLWithPath: executable),
                                                       arguments: arguments, onLine: onLine))
        return MachSSH.Result(status: output.status, output: String(bytes: output.stdout, encoding: .utf8) ?? "")
    }
}
