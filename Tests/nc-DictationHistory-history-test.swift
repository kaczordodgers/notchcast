// notchcast-sources: Tinycast/Features/DictationHistory/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationHistory/Service/DictationHistoryRepository.swift
// notchcast-sources: Tinycast/Features/DictationHistory/Service/DictationHistoryModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Dictation/DictationFamily.swift Tests/dictation-family-stubs.swift
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
        let family = DictationFamily.shared
        module.setStageEnabled = { family.setHistory($0) }
        family.historySink = { module.enqueue(raw: $0, cleaned: $1) }
        let suite = "history-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let controller = NotchcastModuleController([
            .init(requires: [.dictationHistory], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(module.isRunning)
        let stage = DictationCoordinator.transcriptStage!
        for blank in ["", " \n\t "] {
            let unchanged = await stage(blank, nil)
            DictationCoordinator.transcriptObserver?(blank, unchanged)
            precondition(unchanged == blank)
        }
        await module.waitUntilIdle()
        let emptyHistory = try await module.recent()
        precondition(emptyHistory.isEmpty)
        let raw = await stage("fixture raw", nil)
        DictationCoordinator.transcriptObserver?("fixture raw", raw)
        precondition(raw == "fixture raw")
        await module.waitUntilIdle()
        let entries = try await module.recent()
        precondition(entries.count == 1 && entries[0].cleaned == "fixture raw")
        try await module.deleteAll()
        family.observeTranscript(raw: "Wyślij raport.", cleaned: "Send the report.")
        await module.waitUntilIdle()
        let english = try await module.recent()
        precondition(english.count == 1 && english[0].cleaned == "Send the report.")
        precondition(english[0].raw == "Wyślij raport.")
        let backup = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        precondition(backup.isExcludedFromBackup == true)
        family.setCleanup(true)
        module.stop()
        precondition(DictationCoordinator.transcriptStage != nil)
        family.setCleanup(false)
        precondition(DictationCoordinator.transcriptStage == nil)
        family.setCleanup(true)
        module.start()
        family.setCleanup(false)
        precondition(DictationCoordinator.transcriptStage != nil)
        let retained = await DictationCoordinator.transcriptStage!("history only", nil)
        DictationCoordinator.transcriptObserver?("history only", retained)
        precondition(retained == "history only")
        await module.waitUntilIdle()
        try await module.deleteAll()
        await module.record(raw: entries[0].raw, cleaned: entries[0].cleaned)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)
        precondition((permissions[.posixPermissions] as? Int) == 0o700)
        let history = directory.appendingPathComponent("history.jsonl")
        let filePermissions = try FileManager.default.attributesOfItem(atPath: history.path)
        precondition((filePermissions[.posixPermissions] as? Int) == 0o600)
        let pending = directory.appendingPathComponent("pending.jsonl")
        await module.waitUntilIdle()
        let current = try repository.recent()
        try JSONEncoder().encode(current[0]).write(to: pending)
        let recovered = try repository.recent()
        precondition(recovered.count == 1)
        let future = DictationHistoryRepository(directory: directory, now: { date.addingTimeInterval(91 * 86_400) })
        let expired = try future.recent()
        precondition(expired.isEmpty)
        preferences.set(.dictationHistory, false)
        controller.run()
        precondition(!module.isRunning)
        await module.waitUntilIdle()
        await module.record(raw: "disabled fixture", cleaned: "disabled fixture")
        let disabled = try repository.recent()
        precondition(disabled.isEmpty)
        preferences.set(.dictationHistory, true)
        controller.run()
        await module.record(raw: "fallback fixture", cleaned: "fallback fixture")
        await module.waitUntilIdle()
        let fallback = try repository.recent()
        precondition(fallback.count == 1)
        try await module.deleteAll()
        let deleted = try await module.recent()
        precondition(deleted.isEmpty)
        let old = DictationHistoryEntry(id: UUID(), date: date.addingTimeInterval(-91 * 86_400),
                                       raw: "expired", cleaned: "expired")
        for turningOn in [true, false] {
            try JSONEncoder().encode(old).write(to: history)
            if turningOn { module.start() } else { module.stop() }
            await module.waitUntilIdle()
            let pruned = try Data(contentsOf: history)
            precondition(pruned.isEmpty)
        }
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        module.start()
        var failures = 0
        module.onFailure = { failures += 1 }
        let fallbackText = await DictationCoordinator.transcriptStage!("survives failure", nil)
        DictationCoordinator.transcriptObserver?("survives failure", fallbackText)
        precondition(fallbackText == "survives failure")
        await module.waitUntilIdle()
        precondition(failures > 0)
        print("PASS history: permissions, recovery, retention, switch lifecycle, fallback, deletion")
    }
}
