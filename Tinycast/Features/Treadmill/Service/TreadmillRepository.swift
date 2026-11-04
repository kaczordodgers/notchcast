import Foundation

struct TreadmillRepository: Sendable {
    let directory: URL
    var legacyDirectories: [URL] = []
    var legacyLubeDirectory: URL?

    @concurrent
    func load(calendar: Calendar) async throws -> TreadmillArchive {
        let url = directory.appending(path: "treadmill.json")
        var archive = TreadmillArchive()
        if let data = try readIfPresent(url) {
            archive = try JSONDecoder().decode(TreadmillArchive.self, from: data)
            guard archive.isValid else { throw TreadmillFailure.invalidHistory }
        }
        try Task.checkCancellation()
        guard !archive.importedLegacy else { return archive }
        var records: [TreadmillRecord] = []
        for folder in legacyDirectories {
            let history = folder.appending(path: "history.jsonl")
            let historyData = try readIfPresent(history)
            if let historyData { records += TreadmillRecord.parseJSONLines(historyData) }
        }
        if let folder = legacyLubeDirectory {
            let lube = folder.appending(path: "lube.json")
            if let data = try readIfPresent(lube) {
                let mark = try JSONDecoder().decode(LubeMark.self, from: data).remindedKm
                guard mark.isFinite, (0...253_402_300_799).contains(mark) else { throw TreadmillFailure.invalidHistory }
                archive.lubricatedKm = max(archive.lubricatedKm, mark)
            } else if FileManager.default.fileExists(atPath: folder.path) {
                archive.lubricatedKm = max(archive.lubricatedKm, 400)
            }
        }
        archive.records = TreadmillImport.merge(records, into: archive.records, calendar: calendar)
        archive.importedLegacy = true
        return archive
    }

    @concurrent
    func save(_ archive: TreadmillArchive) async throws {
        guard archive.isValid else { throw TreadmillFailure.invalidHistory }
        let data = try JSONEncoder().encode(archive)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "treadmill.json"), options: .atomic)
    }

    private struct LubeMark: Decodable {
        let remindedKm: Double
        enum CodingKeys: String, CodingKey { case remindedKm = "reminded_km" }
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile { return nil }
    }
}
