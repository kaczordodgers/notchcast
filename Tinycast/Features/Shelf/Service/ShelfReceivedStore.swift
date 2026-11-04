import Foundation

struct ShelfReceivedStore: Sendable {
    let directory: URL

    @concurrent
    func receive(_ item: ShelfItem) async throws -> URL {
        try ShelfEngine.validate(item)
        try Task.checkCancellation()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(item.fingerprint + ".json")
        if manager.fileExists(atPath: destination.path) { return destination }
        let entries = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard entries.count < ShelfEngine.maximumItems else { throw ShelfEngine.Failure.full }
        try Task.checkCancellation()
        try JSONEncoder().encode(item).write(to: destination, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }
}
