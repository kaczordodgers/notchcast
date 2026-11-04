import Foundation

struct ClearNotificationsRunner: Sendable {
    typealias Executor = @Sendable (String) async throws -> String

    private let execute: Executor

    init(execute: @escaping Executor = ClearNotificationsExecutor.execute) {
        self.execute = execute
    }

    func run(accessibilityGranted: Bool) async throws -> Int {
        try Task.checkCancellation()
        guard accessibilityGranted else { throw ClearNotificationsFailure.accessibilityRequired }
        let output = try await execute(ClearNotificationsScript.source)
        try Task.checkCancellation()
        guard let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)), count >= 0 else {
            throw ClearNotificationsFailure.invalidResult
        }
        return count
    }
}
