import Foundation

struct CatalogShellCommandRunner: Sendable {
    struct Request: Sendable, Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    struct Result: Sendable, Equatable {
        let exitStatus: Int32
        let standardOutput: Data
        let standardError: Data

        var succeeded: Bool { exitStatus == 0 }
    }

    let processRunner: @Sendable (Request) async throws -> Result

    func run(_ entry: HostCommandCatalog.Entry, arguments: [String] = []) async throws -> Result {
        try Task.checkCancellation()
        let result = try await processRunner(Request(
            executable: entry.executable, arguments: entry.arguments + arguments,
            workingDirectory: entry.workingDirectory))
        try Task.checkCancellation()
        return result
    }
}
