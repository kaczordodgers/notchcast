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
        guard let output = String(bytes: result.stdout, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let error = String(decoding: result.stderr.prefix(limit), as: UTF8.self)
        let cut = result.stderr.count > limit
        return (result.signaled ? 128 + result.status : result.status, output, cut ? error + "\n[truncated]" : error)
    }

    /// A tool past its budget reports `.timedOut`; only a failure to start or read throws.
    static func optimize(_ request: CleanOptimizeRequest) async throws -> CleanOptimizeRequest.Result {
        do {
            return .exited(try await run(request.executable, request.arguments, timeout: request.timeout).code)
        } catch ProcessRunner.Failure.timedOut {
            return .timedOut
        }
    }

    /// `nil` when lsof gave no answer (timed out or errored), so the state reads as unknown.
    static func idle(_ path: URL, recursive: Bool = false,
                     tool: URL = URL(fileURLWithPath: "/usr/sbin/lsof"), timeout: TimeInterval = 5) async throws -> Bool? {
        let result: (code: Int32, output: String, error: String)
        do {
            result = try await run(tool, ["-nP", "-t"] + (recursive ? ["+D", path.path] : ["--", path.path]),
                timeout: timeout)
        } catch ProcessRunner.Failure.timedOut {
            return nil
        }
        guard result.error.isEmpty else { return nil }
        if result.code == 0 { return false }
        return result.code == 1 && result.output.isEmpty ? true : nil
    }
}
