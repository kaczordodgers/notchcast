import Foundation

enum KatanaToneRepository {
    @concurrent
    static func backup(_ tone: KatanaTone, to file: URL) async throws {
        let data = try JSONEncoder().encode(tone)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    @concurrent
    static func load(from url: URL) async throws -> [KatanaTone] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try read(url)
        return try JSONDecoder().decode([KatanaTone].self, from: data)
    }

    @concurrent
    static func importFiles(_ urls: [URL], into library: URL) async throws -> [KatanaTone] {
        guard !urls.isEmpty else { throw KatanaError.invalidData }
        let imported = try urls.flatMap { url in
            try KatanaToneImporter.read(read(url), fileExtension: url.pathExtension)
        }
        var tones = try await load(from: library)
        for tone in imported where !tones.contains(tone) { tones.append(tone) }
        let data = try JSONEncoder().encode(tones)
        guard data.count <= KatanaToneImporter.maximumBytes else { throw KatanaError.invalidData }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: library, options: .atomic)
        return tones
    }

    private static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw KatanaError.invalidData }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size <= KatanaToneImporter.maximumBytes else { throw KatanaError.invalidData }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: KatanaToneImporter.maximumBytes + 1) ?? Data()
        guard data.count <= KatanaToneImporter.maximumBytes else { throw KatanaError.invalidData }
        return data
    }
}
