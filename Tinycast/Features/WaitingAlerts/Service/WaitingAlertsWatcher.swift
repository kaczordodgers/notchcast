import Foundation
import CoreServices

@MainActor
protocol WaitingAlertsWatching: AnyObject {
    func start(path: String, changed: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

@MainActor
final class WaitingAlertsWatcher: WaitingAlertsWatching {
    private var stream: FSEventStreamRef?
    private var changed: (@MainActor () -> Void)?

    func start(path: String, changed: @escaping @MainActor () -> Void) -> Bool {
        stop()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
            return false
        }
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                          retain: nil, release: nil, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated {
                Unmanaged<WaitingAlertsWatcher>.fromOpaque(info).takeUnretainedValue().changed?()
            }
        }, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.5,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)) else { return false }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { stop(); return false }
        return true
    }

    func stop() {
        changed = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
