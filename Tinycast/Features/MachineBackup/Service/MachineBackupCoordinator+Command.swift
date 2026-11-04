import Foundation

extension MachineBackupCoordinator {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "mach-backup-run-now", name: String(localized: "Run Backup Now"),
        sfSymbol: "externaldrive.badge.timemachine",
        isEnabled: {
            NotchcastPreferences.shared.isOn(.backupRunNow) && NotchcastCore.machineBackup.configuration != nil
        },
        run: { NotchcastCore.machineBackup.runCommand() })

    func runCommand() {
        guard commandTask == nil else {
            showMessage(String(localized: "A backup operation is already in progress."), .danger)
            return
        }
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { commandTask = nil }
            do {
                try await runNow()
                showMessage(String(localized: "Backup requested."), .success)
            } catch is CancellationError {
                return
            } catch MachineBackupFailure.configuration {
                showMessage(String(localized: "Machine backup is not configured."), .danger)
            } catch MachineBackupFailure.disabled {
                showMessage(String(localized: "Machine backup is disabled."), .danger)
            } catch MachineBackupFailure.busy {
                showMessage(String(localized: "A backup operation is already in progress."), .danger)
            } catch {
                showMessage(String(localized: "Could not request a backup."), .danger)
            }
        }
    }
}
