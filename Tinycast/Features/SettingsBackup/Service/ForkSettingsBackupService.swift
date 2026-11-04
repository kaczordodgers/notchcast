import Foundation

enum ForkSettingsBackupService {
    @concurrent
    static func save(_ data: Data, folder: URL, day: Int) async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("settings-\(day).plist")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try data.write(to: destination, options: .atomic)
    }
}
