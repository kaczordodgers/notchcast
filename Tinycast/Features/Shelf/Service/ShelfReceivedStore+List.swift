import Foundation

struct ShelfReceivedEntry: Identifiable, Sendable {
    let item: ShelfItem
    let receivedAt: Date
    var id: String { item.fingerprint }
}

extension ShelfReceivedStore {
    @concurrent
    func entries() async throws -> [ShelfReceivedEntry] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "json" }
            .map { url in
                let item = try JSONDecoder().decode(ShelfItem.self, from: Data(contentsOf: url))
                try ShelfEngine.validate(item)
                return ShelfReceivedEntry(item: item, receivedAt:
                    try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast)
            }.sorted {
                if $0.receivedAt == $1.receivedAt { return $0.id < $1.id }
                return $0.receivedAt > $1.receivedAt
            }
    }

    @concurrent
    func remove(_ entry: ShelfReceivedEntry) async throws {
        let url = directory.appendingPathComponent(entry.id + ".json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    @concurrent
    func clear() async throws {
        for entry in try await entries() { try await remove(entry) }
    }

    @concurrent
    func save(_ entry: ShelfReceivedEntry, to destination: URL) async throws -> URL {
        try ShelfEngine.validate(entry.item)
        guard entry.item.kind == .file else { throw ShelfEngine.Failure.invalidItem }
        let name = entry.item.name as NSString
        var suffix = 0
        while true {
            try Task.checkCancellation()
            let filename = suffix == 0 ? entry.item.name :
                name.deletingPathExtension + " (\(suffix))" + (name.pathExtension.isEmpty ? "" : "." + name.pathExtension)
            let url = destination.appendingPathComponent(filename)
            do {
                try entry.item.data.write(to: url, options: [.withoutOverwriting])
                return url
            } catch CocoaError.fileWriteFileExists { suffix += 1 }
        }
    }
}
