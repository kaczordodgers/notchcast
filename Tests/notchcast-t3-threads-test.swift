// notchcast-sources: Tinycast/Features/AgentFleet/AgentFleetExclusion.swift
// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads/T3ThreadsModule.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation
import Synchronization

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@main struct T3ThreadsTest {
    @MainActor static func main() async throws {
        let fixture = Data("""
        {"threads":[{"threadId":"sample","title":"Synthetic","status":"running",
        "model":"example","providerInstanceId":"provider","project":{"title":"Demo"},
        "settled":false,"snoozed":false,"link":"https://example.com/thread",
        "updatedAt":"2026-11-04T10:00:00.000Z","pendingRequestCount":2,"future":true}]}
        """.utf8)
        let threads = try T3ThreadSource.decode(fixture)
        precondition(threads.count == 1 && threads[0].phase == .running)
        precondition(threads[0].model == "example" && threads[0].pendingRequestCount == 2)
        precondition(threads[0].updatedDate != nil && threads[0].settled == false)
        let excluded = Data("""
        [{"threadId":"excluded","project":{"path":"/fixture/\(AgentFleetExclusion.folderName)/work"}}]
        """.utf8)
        let excludedThreads = try T3ThreadSource.decode(excluded)
        precondition(excludedThreads.isEmpty)
        let mappings: [(String, T3Thread.Phase)] = [
            ("queued", .starting), ("preparing", .starting), ("starting", .starting),
            ("running", .running), ("waiting", .waiting_for_input),
            ("waiting_for_input", .waiting_for_input), ("waiting_for_approval", .waiting_for_approval),
            ("completed", .completed), ("failed", .failed), ("cancelled", .failed),
            ("interrupted", .failed), ("future-status", .stale)
        ]
        for (status, phase) in mappings {
            let data = Data("[{\"threadId\":\"sample\",\"status\":\"\(status)\"}]".utf8)
            let decoded = try T3ThreadSource.decode(data)
            precondition(decoded[0].phase == phase)
        }
        for failure in [T3ThreadProcessRunner.Failure.missingBinary, .exit(1)] {
            do {
                _ = try await T3ThreadSource(runner: { throw failure }).read()
                preconditionFailure("Expected CLI failure")
            } catch { precondition(error as? T3ThreadProcessRunner.Failure == failure) }
        }
        let count = Mutex(0)
        let module = T3ThreadsModule(source: .init(runner: {
            count.withLock { $0 += 1 }
            return fixture
        }), interval: .milliseconds(5))
        module.start()
        try await Task.sleep(for: .milliseconds(20))
        precondition(count.withLock { $0 } == 0)
        module.setDemand(true, for: "panel")
        try await Task.sleep(for: .milliseconds(40))
        precondition(count.withLock { $0 } > 1)
        precondition(module.activeThreads.count == 1 && module.pendingThreads.count == 1)
        module.setDemand(false, for: "panel")
        let stoppedCount = count.withLock { $0 }
        try await Task.sleep(for: .milliseconds(20))
        precondition(count.withLock { $0 } == stoppedCount)
        module.stop()
        let continuation = Mutex<CheckedContinuation<Data, Never>?>(nil)
        let delayed = T3ThreadsModule(source: .init(runner: {
            await withCheckedContinuation { value in continuation.withLock { $0 = value } }
        }))
        delayed.setDemand(true, for: "alerts")
        delayed.start()
        while continuation.withLock({ $0 == nil }) { await Task.yield() }
        delayed.stop()
        continuation.withLock { $0?.resume(returning: fixture); $0 = nil }
        try await Task.sleep(for: .milliseconds(20))
        precondition(delayed.threads.isEmpty && delayed.error == nil)
        print("T3 thread fixtures passed")
    }
}
