import Foundation

@MainActor
final class BackupStatusFileMonitor {
    private var source: (any DispatchSourceFileSystemObject)?

    func start(url: URL, changed: @escaping @MainActor () -> Void) {
        stop()
        var directory = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.path), directory.path != "/" {
            directory.deleteLastPathComponent()
        }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.source != nil else { return }
                self?.start(url: url, changed: changed)
                changed()
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    isolated deinit { source?.cancel() }
}
