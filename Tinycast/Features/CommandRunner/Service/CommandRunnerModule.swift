import Foundation

@MainActor
final class CommandRunnerModule: NotchcastModule {
    private(set) var isEnabled = false
    private var operations: [UUID: Task<Void, Never>] = [:]

    func start() { isEnabled = true }

    func stop() {
        isEnabled = false
        operations.values.forEach { $0.cancel() }
        operations.removeAll()
    }

    func perform(_ operation: @escaping @MainActor () async -> Void) {
        guard isEnabled else { return }
        let id = UUID()
        operations[id] = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await operation()
            self?.operations.removeValue(forKey: id)
        }
    }
}
