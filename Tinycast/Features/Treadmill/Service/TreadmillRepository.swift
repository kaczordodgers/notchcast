import Foundation

struct TreadmillRepository: Sendable {
    let directory: URL

    @concurrent
    func load() async throws -> TreadmillArchive {
        let url = directory.appending(path: "treadmill.json")
        guard let data = try readIfPresent(url) else { return TreadmillArchive() }
        let archive = try JSONDecoder().decode(TreadmillArchive.self, from: data)
        guard archive.isValid else { throw TreadmillFailure.invalidHistory }
        try Task.checkCancellation()
        return archive
    }

    @concurrent
    func save(_ archive: TreadmillArchive) async throws {
        guard archive.isValid else { throw TreadmillFailure.invalidHistory }
        let data = try JSONEncoder().encode(archive)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "treadmill.json"), options: .atomic)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile { return nil }
    }
}
