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
        try Task.checkCancellation()
        try JSONEncoder().encode(item).write(to: destination, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let files = try manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])
        let dated: [(url: URL, date: Date)] = try files.filter {
            $0.lastPathComponent != destination.lastPathComponent
        }.map { url in
            let values = try url.resourceValues(forKeys: [.creationDateKey])
            return (url, values.creationDate ?? .distantPast)
        }
        let entries = dated.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.url.lastPathComponent < rhs.url.lastPathComponent }
            return lhs.date < rhs.date
        }
        for entry in entries.prefix(max(0, entries.count + 1 - ShelfEngine.maximumItems)) {
            try manager.removeItem(at: entry.url)
        }
        return destination
    }
}
