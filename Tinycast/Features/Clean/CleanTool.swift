import Foundation

/// How Clean runs git, lsof and the Optimize tools: a fixed environment, and a stop reaches their children.
enum CleanTool {
    private static let limit = 1_048_576

    /// `code` is 128 plus the signal for a killed tool, so a kill never reads as one of its exit codes.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws
        -> (code: Int32, output: String, error: String) {
        let result = try await ProcessRunner.run(.init(executable: executable, arguments: arguments,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "GIT_TERMINAL_PROMPT": "0"],
            stderr: .capture(limit: limit + 1), timeout: .seconds(timeout), outputLimit: limit,
            stopsGroup: true))
        guard let output = String(bytes: result.stdout, encoding: .utf8),
              let error = String(bytes: result.stderr.prefix(limit), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let cut = result.stderr.count > limit
        return (result.signaled ? 128 + result.status : result.status, output, cut ? error + "\n[truncated]" : error)
    }
}
