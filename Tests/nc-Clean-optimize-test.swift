import Foundation
import Synchronization

final class FakeTransports: CleanOptimizeProcessTransport, CleanOptimizeDatabaseTransport {
    struct State {
        var events: [String] = []
        var requests: [CleanOptimizeRequest] = []
        var paths: [URL] = []
        var timeouts: [TimeInterval] = []
    }

    let state = Mutex(State())
    let processResult: CleanOptimizeRequest.Result
    let rows: Int
    let remaining: Int
    let throwsOnCount: Bool

    init(result: CleanOptimizeRequest.Result, rows: Int, remaining: Int, throwsOnCount: Bool) {
        processResult = result
        self.rows = rows
        self.remaining = remaining
        self.throwsOnCount = throwsOnCount
    }

    func run(_ request: CleanOptimizeRequest) async throws -> CleanOptimizeRequest.Result {
        state.withLock {
            $0.events.append(request.executable.lastPathComponent)
            $0.requests.append(request)
        }
        return processResult
    }

    func count(at database: URL, timeout: TimeInterval) async throws -> Int {
        state.withLock {
            $0.events.append("count")
            $0.paths.append(database)
            $0.timeouts.append(timeout)
        }
        if throwsOnCount { throw CocoaError(.fileReadNoPermission) }
        return rows
    }

    func clear(at database: URL, timeout: TimeInterval) async throws -> Int {
        state.withLock {
            $0.events.append("clear")
            $0.paths.append(database)
            $0.timeouts.append(timeout)
        }
        return remaining
    }
}

@main
struct CleanOptimizeTests {
    static func main() async throws {
        precondition(CleanOptimizeTask.allCases == [.quickLook, .downloadHistory, .openWithMenu])
        try await scenario(selected: Set(CleanOptimizeTask.allCases), expectedEvents: [
            "preview-tool", "count", "clear", "menu-tool"
        ], expectedStatuses: [.ran, .ran, .ran])
        try await scenario(result: .exited(7), selected: Set(CleanOptimizeTask.allCases),
                           expectedEvents: ["preview-tool", "count", "clear", "menu-tool"],
                           expectedStatuses: [.failed(.exitCode(7)), .ran, .failed(.exitCode(7))])
        try await scenario(rows: 0, selected: [.downloadHistory], expectedEvents: ["count"],
                           expectedStatuses: [.skipped(.alreadyEmpty)])
        try await scenario(selected: [.openWithMenu], expectedEvents: ["menu-tool"],
                           expectedStatuses: [.ran])
        try await scenario(selected: [], expectedEvents: [], expectedStatuses: [])
        try await scenario(remaining: 2, selected: [.downloadHistory],
                           expectedEvents: ["count", "clear"], expectedStatuses: [.failed(.remainingRows(2))])
        try await scenario(throwsOnCount: true, selected: [.downloadHistory, .openWithMenu],
                           expectedEvents: ["count", "menu-tool"],
                           expectedStatuses: [.failed(.transportFailed), .ran])
        try await scenario(result: .timedOut, selected: [.quickLook, .openWithMenu],
                           expectedEvents: ["preview-tool", "menu-tool"],
                           expectedStatuses: [.failed(.timedOut), .failed(.timedOut)])
        print("PASS: defaults/order; failures continue; selected only; skipped excluded; requests bounded")
    }

    static func scenario(result: CleanOptimizeRequest.Result = .exited(0), rows: Int = 3,
                         remaining: Int = 0, throwsOnCount: Bool = false,
                         selected: Set<CleanOptimizeTask>, expectedEvents: [String],
                         expectedStatuses: [CleanOptimizeOutcome.Status]) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("fake-home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                preconditionFailure("Temporary fixture cleanup failed: \(error)")
            }
        }
        let fake = FakeTransports(result: result, rows: rows, remaining: remaining,
                                  throwsOnCount: throwsOnCount)
        let service = CleanOptimizeService(home: home,
            quickLookTool: root.appendingPathComponent("preview-tool"),
            openWithTool: root.appendingPathComponent("menu-tool"), process: fake, database: fake)
        let outcomes = try await service.run(selected)
        if selected.count == 3 { precondition(outcomes.map(\.task) == [.quickLook, .downloadHistory, .openWithMenu]) }
        precondition(outcomes.map(\.status) == expectedStatuses)
        fake.state.withLock { state in
            precondition(state.events == expectedEvents)
            for request in state.requests {
                precondition(request.environment.isEmpty && request.executable.path.hasPrefix(root.path))
                if request.executable.lastPathComponent == "preview-tool" {
                    precondition(request.arguments == ["-r", "cache"] && request.timeout == 60)
                } else {
                    precondition(request.arguments == ["-r", "-domain", "local", "-domain", "user"])
                    precondition(request.timeout == 180)
                }
            }
            precondition(state.paths.allSatisfy { $0.path.hasPrefix(home.path + "/") })
            precondition(state.timeouts.allSatisfy { $0 == 10 || $0 == 50 })
        }
    }
}
