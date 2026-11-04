import Foundation

extension MachineBackupCoordinator {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "mach-backup-run-now", name: String(localized: "Run Backup Now"),
        sfSymbol: "externaldrive.badge.timemachine",
        isEnabled: { NotchcastPreferences.shared.isOn(.backupRunNow) },
        run: { NotchcastCore.machineBackup.runCommand() })

    func runCommand() {
        guard commandTask == nil else {
            showMessage(String(localized: "A backup operation is already in progress."))
            return
        }
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { commandTask = nil }
            do {
                try await runNow()
                showMessage(String(localized: "Backup requested."))
            } catch is CancellationError {
                return
            } catch MachineBackupFailure.configuration {
                showMessage(String(localized: "Machine backup is not configured."))
            } catch MachineBackupFailure.disabled {
                showMessage(String(localized: "Machine backup is disabled."))
            } catch MachineBackupFailure.busy {
                showMessage(String(localized: "A backup operation is already in progress."))
            } catch {
                showMessage(String(localized: "Could not request a backup."))
            }
        }
    }
}
