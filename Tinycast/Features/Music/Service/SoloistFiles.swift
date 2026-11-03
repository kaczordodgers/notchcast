import Foundation

struct SoloistFiles: Sendable {
    let root: URL

    init(root: URL = AppPaths.applicationSupport().appending(path: "soloist", directoryHint: .isDirectory)) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    var builds: URL { root.appending(path: "builds", directoryHint: .isDirectory) }
    var data: URL { root.appending(path: "data", directoryHint: .isDirectory) }
    var cache: URL { root.appending(path: "cache", directoryHint: .isDirectory) }
    var portFile: URL { data.appending(path: "ws.port") }
    var addressFile: URL { data.appending(path: "ws.addr") }
    var childRecord: URL { root.appending(path: "notchcast-soloist.pid") }
    var rejectedArchive: URL { root.appending(path: "rejected.sha256") }

    func makeFolders() throws {
        for folder in [builds, data, cache] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
    }

    func readPort() -> Int? {
        guard let text = try? String(contentsOf: portFile, encoding: .utf8),
              let port = UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines)), port != 0 else { return nil }
        if let address = try? String(contentsOf: addressFile, encoding: .utf8),
           address.trimmingCharacters(in: .whitespacesAndNewlines) != "127.0.0.1" { return nil }
        return Int(port)
    }

    func clearPort() throws {
        for file in [portFile, addressFile] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    func ownsExecutable(_ path: String) -> Bool {
        let executable = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        let directory = builds.standardizedFileURL.resolvingSymlinksInPath()
        return executable.lastPathComponent == "soloist" && executable.path.hasPrefix(directory.path + "/")
    }

    func recordedChild() -> Int32? {
        guard let text = try? String(contentsOf: childRecord, encoding: .utf8) else { return nil }
        return Int32(text)
    }

    func recordChild(_ pid: Int32) throws {
        try String(pid).write(to: childRecord, atomically: true, encoding: .utf8)
    }

    func forgetChild(_ pid: Int32) {
        guard recordedChild() == pid else { return }
        try? FileManager.default.removeItem(at: childRecord)
    }

    func arguments(key: String, deviceName: String) -> [String] {
        ["--device-name", deviceName, "--api-key", key, "--ws", "127.0.0.1:0", "--cache-size", "512",
         "--data-dir", data.path, "--cache-dir", cache.path]
    }
}
