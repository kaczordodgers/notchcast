import Foundation
import Observation

@MainActor @Observable
final class ForkSettingsBackupModule: NotchcastModule {
    private(set) var failed = false
    private var partialDay: Int?
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let (values, skipped) = ForkSettingsBackupState.liveSnapshot()
                    let now = Date.now
                    let data = try ForkSettingsBackupEngine.encode(values, created: now)
                    let day = Int(now.timeIntervalSince1970 / 86_400)
                    let wrote = try await ForkSettingsBackupService.save(
                        data, folder: NotchcastIdentity.supportRoot.appendingPathComponent("fork-settings-backups"),
                        day: day, replacing: partialDay == day)
                    guard !Task.isCancelled else { return }
                    if wrote { partialDay = skipped.isEmpty ? nil : day }
                    failed = partialDay == day
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                }
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    func stop() {
        ForkSettingsBackupCoordinator.shared.stop()
        task?.cancel()
        task = nil
    }
}
