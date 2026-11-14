import Foundation

@MainActor
enum FinderCopyService {
    static func copySelection(
        changeCount: () -> Int, fileCount: () -> Int, copy: () -> Void,
        isCurrent: () -> Bool,
        wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(20)) }
    ) async -> Int? {
        let before = changeCount()
        copy()
        for _ in 0..<25 {
            do { try await wait() } catch { return nil }
            guard isCurrent() else { return nil }
            let copied = changeCount()
            guard copied != before else { continue }
            let count = fileCount()
            guard changeCount() == copied, count > 0 else { return nil }
            return copied
        }
        return nil
    }
}
