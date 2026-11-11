// Adapted from Damian Tools (GPL-3.0-or-later)
import Foundation

struct CleanOptimizeService: Sendable {
    let home: URL
    let quickLookTool: URL
    let openWithTool: URL
    let process: any CleanOptimizeProcessTransport
    let database: any CleanOptimizeDatabaseTransport

    @concurrent func run(_ selected: Set<CleanOptimizeTask>) async throws -> [CleanOptimizeOutcome] {
        var outcomes: [CleanOptimizeOutcome] = []
        for task in CleanOptimizeTask.allCases where selected.contains(task) {
            try Task.checkCancellation()
            let status: CleanOptimizeOutcome.Status
            do {
                switch task {
                case .quickLook:
                    status = try await command(quickLookTool, arguments: ["-r", "cache"], timeout: 60)
                case .downloadHistory:
                    status = try await clearHistory()
                case .openWithMenu:
                    status = try await command(openWithTool,
                        arguments: ["-r", "-domain", "local", "-domain", "user"], timeout: 180)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                status = .failed(.transportFailed)
            }
            try Task.checkCancellation()
            outcomes.append(CleanOptimizeOutcome(task: task, status: status))
        }
        return outcomes
    }

    private func command(_ tool: URL, arguments: [String], timeout: TimeInterval) async throws
        -> CleanOptimizeOutcome.Status {
        guard tool.isFileURL, tool.path.hasPrefix("/") else { return .failed(.invalidExecutable) }
        let result = try await process.run(CleanOptimizeRequest(
            executable: tool, arguments: arguments, timeout: timeout))
        switch result {
        case .exited(0): return .ran
        case .exited(let code): return .failed(.exitCode(code))
        case .timedOut: return .failed(.timedOut)
        }
    }

    private func clearHistory() async throws -> CleanOptimizeOutcome.Status {
        let path = home.appendingPathComponent(
            "Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
        let rows = try await database.count(at: path, timeout: 10)
        try Task.checkCancellation()
        guard rows >= 0 else { return .failed(.invalidRowCount) }
        guard rows > 0 else { return .skipped(.alreadyEmpty) }
        let remaining = try await database.clear(at: path, timeout: 50)
        guard remaining >= 0 else { return .failed(.invalidRowCount) }
        return remaining == 0 ? .ran : .failed(.remainingRows(remaining))
    }
}
