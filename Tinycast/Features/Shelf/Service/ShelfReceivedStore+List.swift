import Darwin
import Foundation

struct ShelfReceivedEntry: Identifiable, Sendable {
    let item: ShelfItem
    let receivedAt: Date
    var id: String { item.fingerprint }
}

extension ShelfReceivedStore {
    @concurrent
    func modificationDate() async throws -> Date? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        return try directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    @concurrent
    func entries() async throws -> [ShelfReceivedEntry] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ShelfReceivedEntry? in
                guard let data = try? Data(contentsOf: url),
                      let item = try? JSONDecoder().decode(ShelfItem.self, from: data),
                      (try? ShelfEngine.validate(item)) != nil else { return nil }
                return ShelfReceivedEntry(item: item, receivedAt:
                    (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast)
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
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            try Task.checkCancellation()
            try manager.removeItem(at: url)
        }
    }

    @concurrent
    func save(_ entry: ShelfReceivedEntry, to destination: URL) async throws -> URL {
        try ShelfEngine.validate(entry.item)
        guard entry.item.kind == .file, !entry.item.name.hasPrefix("."),
              !entry.item.name.unicodeScalars.contains(where: {
                  (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
              }) else { throw ShelfEngine.Failure.invalidItem }
        let name = entry.item.name as NSString
        var suffix = 0
        while true {
            try Task.checkCancellation()
            let ending = suffix == 0 ? "" : " (\(suffix))"
            let ext = name.pathExtension.isEmpty ? "" : "." + name.pathExtension
            var base = name.deletingPathExtension
            while (base + ending + ext).utf8.count > 255 {
                guard !base.isEmpty else { throw ShelfEngine.Failure.invalidItem }
                base.removeLast()
            }
            guard !base.isEmpty else { throw ShelfEngine.Failure.invalidItem }
            let filename = base + ending + ext
            let url = destination.appendingPathComponent(filename)
            do {
                try entry.item.data.write(to: url, options: [.withoutOverwriting])
                let status = WebRules.stampQuarantine(url.path)
                guard status == 0 else {
                    let failure = POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
                    try FileManager.default.removeItem(at: url)
                    throw failure
                }
                return url
            } catch CocoaError.fileWriteFileExists { suffix += 1 }
        }
    }
}
