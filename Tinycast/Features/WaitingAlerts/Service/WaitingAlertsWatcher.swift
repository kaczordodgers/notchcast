import Foundation
import CoreServices

@MainActor
protocol WaitingAlertsWatching: AnyObject {
    func start(path: String, changed: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

/// Reports changes to files directly inside `path`, where T3 keeps its state database.
/// Writes in subfolders are ignored.
@MainActor
final class WaitingAlertsWatcher: WaitingAlertsWatching {
    private var watcher: FileSystemWatcher?

    func start(path: String, changed: @escaping @MainActor () -> Void) -> Bool {
        stop()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
            return false
        }
        // FSEvents reports real paths (`/private/var/…`), so compare against the real root.
        guard let resolved = realpath(path, nil) else { return false }
        let root = String(cString: resolved) + "/"
        free(resolved)
        watcher = FileSystemWatcher(
            paths: [path], since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow), queue: .main
        ) { events in
            guard events.contains(where: {
                $0.has(kFSEventStreamEventFlagRootChanged)
                    || ($0.path.hasSuffix("/") ? $0.path : $0.path + "/") == root
            }) else { return }
            Task { @MainActor in changed() }
        }
        return watcher != nil
    }

    func stop() { watcher = nil }
}
