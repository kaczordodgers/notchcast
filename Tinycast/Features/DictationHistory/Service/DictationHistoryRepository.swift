import Foundation

struct DictationHistoryRepository: Sendable {
    let directory: URL
    let now: @Sendable () -> Date
    private var history: URL { directory.appendingPathComponent("history.jsonl") }
    private var pending: URL { directory.appendingPathComponent("pending.jsonl") }

    func record(raw: String, cleaned: String) throws {
        try prepare()
        try recover()
        let entry = DictationHistoryEntry(id: UUID(), date: now(), raw: raw, cleaned: cleaned)
        try write([entry], to: pending)
        try recover()
    }

    func recent(limit: Int = 100) throws -> [DictationHistoryEntry] {
        try prepare()
        let cutoff = now().addingTimeInterval(-90 * 86_400)
        return Array(try loadEntries().filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }

    func maintain() throws {
        try prepare()
        try recover()
    }

    func deleteAll() throws {
        try prepare()
        for file in [pending, history] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix(".stage-") {
            try manager.removeItem(at: file)
        }
    }

    private func recover() throws {
        let entries = try loadEntries()
        let cutoff = now().addingTimeInterval(-90 * 86_400)
        try write(entries.filter { $0.date >= cutoff }, to: history)
        if FileManager.default.fileExists(atPath: pending.path) {
            try FileManager.default.removeItem(at: pending)
        }
    }

    private func loadEntries() throws -> [DictationHistoryEntry] {
        var entries = try load(history)
        for entry in try load(pending) where !entries.contains(where: { $0.id == entry.id }) {
            entries.append(entry)
        }
        return entries
    }

    private func load(_ url: URL) throws -> [DictationHistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try Data(contentsOf: url).split(separator: 10).compactMap {
            try? JSONDecoder().decode(DictationHistoryEntry.self, from: Data($0))
        }
    }

    private func write(_ entries: [DictationHistoryEntry], to url: URL) throws {
        var data = Data()
        for entry in entries {
            data.append(try JSONEncoder().encode(entry))
            data.append(10)
        }
        let temporary = directory.appendingPathComponent(".stage-" + UUID().uuidString)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); unlink(temporary.path) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
        let folder = open(directory.path, O_RDONLY)
        guard folder >= 0 else { throw POSIXError(.EIO) }
        defer { close(folder) }
        guard fsync(folder) == 0 else { throw POSIXError(.EIO) }
    }
}
