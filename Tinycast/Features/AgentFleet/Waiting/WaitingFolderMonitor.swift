import CoreServices
import Foundation

@MainActor
final class WaitingFolderMonitor: WaitingFolderWatching {
    private final class Handler: Sendable {
        let changed: @MainActor @Sendable () -> Void
        init(_ changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }
    }

    private var stream: FSEventStreamRef?

    func start(folder: URL, changed: @escaping @MainActor @Sendable () -> Void) throws {
        stop()
        let box = Unmanaged.passRetained(Handler(changed))
        var context = FSEventStreamContext(version: 0, info: box.toOpaque(), retain: nil,
            release: { $0.map { Unmanaged<Handler>.fromOpaque($0).release() } }, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, paths, _, _ in
            guard let info, count > 0,
                  let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String],
                  paths.contains(where: { !URL(filePath: $0).pathComponents.contains("agent-2784f2ac") })
            else { return }
            let changed = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().changed
            Task { @MainActor in changed() }
        }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else {
            box.release()
            throw CocoaError(.fileReadUnknown)
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            stop()
            throw CocoaError(.fileReadUnknown)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    isolated deinit { stop() }
}
