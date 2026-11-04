import Foundation

enum EditorRecoveryService {
    @MainActor
    static func flush(
        _ document: EditorDocumentSession, directory: URL,
        save: (@MainActor () async throws -> Void)? = nil
    ) async throws -> URL? {
        do {
            if let save { try await save() } else { try await document.flush() }
            return nil
        } catch {
            return try await write(document.source, name: document.url.lastPathComponent, directory: directory)
        }
    }

    @concurrent
    private static func write(_ source: String, name: String, directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let url = directory.appendingPathComponent("\(name)-\(stamp)-\(UUID().uuidString).txt")
        try Data(source.utf8).write(to: url, options: .atomic)
        return url
    }
}
