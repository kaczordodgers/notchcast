import Foundation

nonisolated struct FinderService: Sendable {
    func libraryHidden(home: URL) throws -> Bool {
        let values = try home.appendingPathComponent("Library").resourceValues(forKeys: [.isHiddenKey])
        guard let hidden = values.isHidden else { throw CocoaError(.fileReadUnknown) }
        return hidden
    }
}
