import Foundation
import Observation

@MainActor
@Observable
final class DictationHistoryModule: NotchcastModule {
    private(set) var revision = 0
    private let repository: DictationHistoryRepository
    private let queue = DispatchQueue(label: "dictation-history")
    private(set) var isRunning = false
    var onFailure: (() -> Void)?
    var setStageEnabled: (Bool) -> Void = { _ in }
    private var pendingWork: Task<Void, Never>?

    init(repository: DictationHistoryRepository) {
        self.repository = repository
    }

    func start() {
        isRunning = true
        setStageEnabled(true)
        schedule { await $0.maintain() }
    }

    func stop() {
        isRunning = false
        setStageEnabled(false)
        schedule { await $0.maintain() }
    }

    func enqueue(raw: String, cleaned: String) {
        guard isRunning else { return }
        schedule { module in
            do {
                try await module.perform { try $0.record(raw: raw, cleaned: cleaned) }
                module.revision += 1
            }
            catch { module.onFailure?() }
        }
    }

    func waitUntilIdle() async { await pendingWork?.value }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async { if phase == .afterRootDrain { await waitUntilIdle() } }

    private func schedule(_ operation: @escaping @MainActor (DictationHistoryModule) async -> Void) {
        let previous = pendingWork
        pendingWork = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    func maintain() async {
        do { _ = try await recent(limit: 0) }
        catch { onFailure?() }
    }

    func record(raw: String, cleaned: String) async {
        guard isRunning else { return }
        do {
            try await perform { try $0.record(raw: raw, cleaned: cleaned) }
            revision += 1
        } catch { onFailure?() }
    }

    func recent(limit: Int = 100) async throws -> [DictationHistoryEntry] {
        try await perform { try $0.recent(limit: limit) }
    }

    func deleteAll() async throws {
        try await perform { try $0.deleteAll() }
        revision += 1
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (DictationHistoryRepository) throws -> T
    ) async throws -> T {
        let repository = repository
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation(repository) })
            }
        }
    }
}
