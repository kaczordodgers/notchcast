import Foundation

extension BackupStatusModule {
    convenience init(path: @escaping @MainActor () -> String, post: @escaping @MainActor (String) -> Void) {
        let monitor = BackupStatusFileMonitor()
        self.init(read: {
            let url = URL(fileURLWithPath: path())
            let task = Task.detached { try Data(contentsOf: url) }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }, watch: { changed in
            let url = URL(fileURLWithPath: path())
            monitor.start(url: url, changed: changed)
            return { monitor.stop() }
        }, schedule: { deadline, action in
            let task = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
            return { task.cancel() }
        }, configurationNotice: {
            path().hasPrefix("/") ? nil : String(localized: "Backup status path is not configured.", table: "Notchcast")
        }, post: post)
    }
}
