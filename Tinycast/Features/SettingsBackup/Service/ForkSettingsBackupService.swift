import Foundation
import Darwin

enum ForkSettingsBackupService {
    struct Copy: Identifiable, Sendable {
        let name: String
        let date: Date
        let size: Int?
        let valid: Bool
        var id: String { name }
    }

    @concurrent
    static func copies(folder: URL) async throws -> [Copy] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var copies: [Copy] = []
        for name in names where ForkSettingsBackupEngine.newest(in: [name]) != nil {
            try Task.checkCancellation()
            let day = Double(name.dropFirst(12).dropLast(6)) ?? 0
            var date = Date(timeIntervalSince1970: day * 86_400)
            var size: Int?
            var valid = false
            if let data = try? await read(folder: folder, name: name) {
                size = data.count
                if (try? ForkSettingsBackupEngine.decode(data)) != nil {
                    let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                    date = root?["created"] as? Date ?? date
                    valid = true
                }
            }
            copies.append(Copy(name: name, date: date, size: size, valid: valid))
        }
        return copies.sorted { $0.date == $1.date ? $0.name > $1.name : $0.date > $1.date }
    }

    @concurrent
    static func read(folder: URL, name: String) async throws -> Data {
        guard ForkSettingsBackupEngine.newest(in: [name]) == name else {
            throw ForkSettingsBackupEngine.Failure.invalidArchive
        }
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
