import Foundation

struct FinderCutSession: Sendable {
    private(set) var clipboardChangeCount: Int?
    private(set) var fileCount = 0

    mutating func mark(changeCount: Int, fileCount: Int) {
        clear()
        guard fileCount > 0 else { return }
        clipboardChangeCount = changeCount
        self.fileCount = fileCount
    }

    mutating func take(changeCount: Int) -> Bool {
        defer { clear() }
        return clipboardChangeCount == changeCount
    }

    mutating func clear() {
        clipboardChangeCount = nil
        fileCount = 0
    }
}
