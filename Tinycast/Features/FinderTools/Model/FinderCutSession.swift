import Foundation

struct FinderCutSession: Sendable {
    private(set) var clipboardChangeCount: Int?

    mutating func mark(changeCount: Int, fileCount: Int) {
        clear()
        guard fileCount > 0 else { return }
        clipboardChangeCount = changeCount
    }

    mutating func take(changeCount: Int) -> Bool {
        defer { clear() }
        return clipboardChangeCount == changeCount
    }

    mutating func clear() {
        clipboardChangeCount = nil
    }
}
