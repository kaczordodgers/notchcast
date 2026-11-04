// notchcast-sources: Tinycast/Features/DictationHistory/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationHistory/Service/*.swift

import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }

@main struct HistoryModuleTest {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DictationHistoryRepository(directory: directory, now: {
            Date(timeIntervalSince1970: 2_000_000_000)
        })
        let module = DictationHistoryModule(repository: repository)
        var stages: [Bool] = []
        var failures = 0
        module.setStageEnabled = { stages.append($0) }
        module.onFailure = { failures += 1 }
        module.enqueue(raw: "disabled", cleaned: "disabled")
        module.start()
        module.enqueue(raw: "first", cleaned: "clean first")
        module.enqueue(raw: "second", cleaned: "clean second")
        await module.waitUntilIdle()
        precondition(module.isRunning && stages == [true])
        let entries = try await module.recent()
        precondition(Set(entries.map(\.raw)) == ["first", "second"])
        precondition(entries.contains { $0.raw == "first" && $0.cleaned == "clean first" })
        module.stop()
        module.enqueue(raw: "disabled", cleaned: "disabled")
        await module.record(raw: "disabled", cleaned: "disabled")
        await module.waitUntilIdle()
        precondition(!module.isRunning && stages == [true, false])
        let stopped = try await module.recent()
        precondition(stopped.count == 2)
        try await module.deleteAll()
        let deleted = try await module.recent()
        precondition(deleted.isEmpty && failures == 0)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        module.start()
        await module.waitUntilIdle()
        precondition(failures == 1)
        module.enqueue(raw: "failure", cleaned: "failure")
        await module.waitUntilIdle()
        precondition(failures == 2)
        await module.record(raw: "failure", cleaned: "failure")
        precondition(failures == 3)
        module.stop()
        await module.waitUntilIdle()
        precondition(failures == 4 && stages == [true, false, true, false])
        print("PASS history module lifecycle, queued recordings, deletion and failure reporting")
    }
}
