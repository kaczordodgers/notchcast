import Foundation

@MainActor
final class DictationHistoryModule: NotchcastModule {
    private let repository: DictationHistoryRepository
    private let queue = DispatchQueue(label: "dictation-history")
    private(set) var isRunning = false
    var onFailure: (() -> Void)?

    init(repository: DictationHistoryRepository) {
        self.repository = repository
    }

    func start() { isRunning = true }
    func stop() { isRunning = false }

    func maintain() async {
        do { _ = try await recent(limit: 0) }
        catch { onFailure?() }
    }

    func record(raw: String, cleaned: String) async {
        guard isRunning else { return }
        do {
            try await perform { try $0.record(raw: raw, cleaned: cleaned) }
        } catch { onFailure?() }
    }

    func recent(limit: Int = 100) async throws -> [DictationHistoryEntry] {
        try await perform { try $0.recent(limit: limit) }
    }

    func deleteAll() async throws {
        try await perform { try $0.deleteAll() }
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
