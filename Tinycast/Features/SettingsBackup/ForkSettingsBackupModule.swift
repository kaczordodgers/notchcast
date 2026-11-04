import Foundation
import Observation

@MainActor @Observable
final class ForkSettingsBackupModule: NotchcastModule {
    private(set) var failed = false
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let suite = (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast"
                    let values = UserDefaults.standard.persistentDomain(forName: suite) ?? [:]
                    let now = Date.now
                    let data = try ForkSettingsBackupEngine.encode(values, created: now)
                    try await ForkSettingsBackupService.save(
                        data, folder: AppPaths.applicationSupport().appendingPathComponent("fork-settings-backups"),
                        day: Int(now.timeIntervalSince1970 / 86_400))
                    guard !Task.isCancelled else { return }
                    failed = false
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                }
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
