// notchcast-sources: Tinycast/Features/DictationHistory/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationHistory/Service/DictationHistoryRepository.swift
import Foundation

@main
struct DictationHistoryListTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let repository = DictationHistoryRepository(directory: directory, now: { now })
        for index in (0..<105).reversed() {
            let writer = DictationHistoryRepository(directory: directory, now: {
                now.addingTimeInterval(Double(index) - 105)
            })
            try writer.record(raw: "raw", cleaned: "Entry \(index)")
        }
        let entries = try repository.recent()
        precondition(entries.count == 100)
        precondition(entries.first?.cleaned == "Entry 104")
        precondition(entries.last?.cleaned == "Entry 5")
        precondition(zip(entries, entries.dropFirst()).allSatisfy { $0.date > $1.date })
        try repository.deleteAll()
        let cleared = try repository.recent()
        precondition(cleared.isEmpty)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("history.jsonl"))
        do {
            _ = try repository.recent()
            preconditionFailure("Corrupt history must fail to load")
        } catch {
            precondition(DictationHistoryClearPolicy.isEnabled(
                isLoading: false, isClearing: false, isEmpty: true, loadFailed: true))
        }
        try repository.deleteAll()
        let recovered = try repository.recent()
        precondition(recovered.isEmpty)
        precondition(!DictationHistoryClearPolicy.isEnabled(
            isLoading: false, isClearing: false, isEmpty: true, loadFailed: false))
        precondition(!DictationHistoryClearPolicy.isEnabled(
            isLoading: true, isClearing: false, isEmpty: true, loadFailed: true))
        precondition(!DictationHistoryClearPolicy.isEnabled(
            isLoading: false, isClearing: true, isEmpty: true, loadFailed: true))
        print("PASS history list: newest first, latest 100, clear empties isolated store")
    }
}
