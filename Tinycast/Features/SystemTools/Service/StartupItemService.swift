import Foundation

nonisolated struct StartupItemService: Sendable {
    func read(folder: URL, kind: StartupItem.Kind) throws -> [StartupItem] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { $0.pathExtension == "plist" }.sorted { $0.path < $1.path }.map { url in
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw StartupItem.Failure.readOnly }
                return try StartupItem.decode(Data(contentsOf: url), path: url.path, kind: kind)
            }
    }

    func apply(_ item: StartupItem, enabled: Bool, uid: UInt32, home: String,
               run: ([String]) throws -> Void) throws {
        for arguments in try item.commands(enabled: enabled, uid: uid, home: home) { try run(arguments) }
    }
}
