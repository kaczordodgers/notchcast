import Foundation

extension BackupStatusModule {
    convenience init() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/damian-tools/mac-backup/status.json")
        let monitor = BackupStatusFileMonitor()
        self.init(read: {
            let task = Task.detached { try Data(contentsOf: url) }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }, watch: { changed in
            monitor.start(url: url, changed: changed)
            return { monitor.stop() }
        }, schedule: { deadline, action in
            let task = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
            return { task.cancel() }
        }, post: { IslandActivityCenter.shared.showMessage($0, tone: .neutral, dwell: 8) })
    }
}
