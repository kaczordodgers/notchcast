import Foundation

enum ForkSettingsBackupService {
    @concurrent
    static func latest(folder: URL) async throws -> Data? {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard let name = ForkSettingsBackupEngine.newest(in: names) else { return nil }
        let data = try Data(contentsOf: folder.appendingPathComponent(name))
        try Task.checkCancellation()
        return data
    }

    @concurrent
    static func create(folder: URL) async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @concurrent
    static func save(_ data: Data, folder: URL, day: Int) async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("settings-\(day).plist")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try data.write(to: destination, options: .atomic)
    }
}
