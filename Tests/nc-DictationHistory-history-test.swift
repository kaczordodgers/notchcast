// notchcast-sources: Tinycast/Features/DictationHistory/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationHistory/Service/DictationHistoryRepository.swift
// notchcast-sources: Tinycast/Features/DictationHistory/Service/DictationHistoryModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
import Foundation

@main
struct DictationHistoryTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let repository = DictationHistoryRepository(directory: directory, now: { date })
        let module = DictationHistoryModule(repository: repository)
        let suite = "history-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(preferences.isOn(.dictationHistory))
        let controller = NotchcastModuleController([
            .init(requires: [.dictationHistory], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(module.isRunning)
        await module.record(raw: "fixture raw", cleaned: "fixture cleaned")
        let entries = try await module.recent()
        precondition(entries.count == 1 && entries[0].cleaned == "fixture cleaned")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)
        precondition((permissions[.posixPermissions] as? Int) == 0o700)
        let history = directory.appendingPathComponent("history.jsonl")
        let filePermissions = try FileManager.default.attributesOfItem(atPath: history.path)
        precondition((filePermissions[.posixPermissions] as? Int) == 0o600)
        let pending = directory.appendingPathComponent("pending.jsonl")
        try JSONEncoder().encode(entries[0]).write(to: pending)
        let recovered = try repository.recent()
        precondition(recovered.count == 1)
        let future = DictationHistoryRepository(directory: directory, now: { date.addingTimeInterval(91 * 86_400) })
        let expired = try future.recent()
        precondition(expired.isEmpty)
        preferences.set(.dictationHistory, false)
        controller.run()
        precondition(!module.isRunning)
        await module.record(raw: "disabled fixture", cleaned: "disabled fixture")
        let disabled = try repository.recent()
        precondition(disabled.isEmpty)
        preferences.set(.dictationHistory, true)
        controller.run()
        await module.record(raw: "fallback fixture", cleaned: "fallback fixture")
        let fallback = try repository.recent()
        precondition(fallback.count == 1)
        try await module.deleteAll()
        let deleted = try await module.recent()
        precondition(deleted.isEmpty)
        print("PASS history: permissions, recovery, retention, switch lifecycle, fallback, deletion")
    }
}
