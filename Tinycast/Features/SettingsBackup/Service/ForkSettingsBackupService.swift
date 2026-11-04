import Foundation
import Darwin

enum ForkSettingsBackupService {
    @concurrent
    static func latest(folder: URL) async throws -> Data? {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard let name = ForkSettingsBackupEngine.newest(in: names) else { return nil }
        let url = folder.appendingPathComponent(name)
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ForkSettingsBackupEngine.Failure.invalidArchive }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_size > 0, status.st_size <= ForkSettingsBackupEngine.maximumSize else {
            throw ForkSettingsBackupEngine.Failure.invalidArchive
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: ForkSettingsBackupEngine.maximumSize + 1) ?? Data()
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
        let destination = folder.appendingPathComponent("settings-v2-\(day).plist")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try data.write(to: destination, options: .atomic)
    }
}
