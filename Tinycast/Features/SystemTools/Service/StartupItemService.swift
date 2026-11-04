import Foundation

nonisolated struct StartupItemService: Sendable {
    func status(_ item: StartupItem, uid: UInt32, disabledText: String,
                run: (String, [String]) throws -> String) throws -> StartupItem {
        guard item.kind == .userAgent else { return item }
        let loaded: Bool?
        do {
            _ = try run("/bin/launchctl", ["print", "gui/\(uid)/\(item.label)"])
            loaded = true
        } catch is CancellationError {
            throw CancellationError()
        } catch SystemToolsProcessRunner.Failure.failed(113) {
            loaded = false
        } catch {
            loaded = nil
        }
        return StartupItem(label: item.label, kind: item.kind, path: item.path,
                           program: item.program,
                           disabled: disabledText.contains("\"\(item.label)\" => true"), loaded: loaded)
    }

    func read(folder: URL, kind: StartupItem.Kind) throws -> [StartupItem] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { $0.pathExtension == "plist" }.sorted { $0.path < $1.path }.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                      values.isSymbolicLink != true,
                      let data = try? Data(contentsOf: url) else { return nil }
                return try? StartupItem.decode(data, path: url.path, kind: kind)
            }
    }

    func apply(_ item: StartupItem, enabled: Bool, uid: UInt32, home: String,
               run: ([String]) throws -> Void) throws {
        for arguments in try item.commands(enabled: enabled, uid: uid, home: home) { try run(arguments) }
    }
}
