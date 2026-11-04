import AppKit

@MainActor
final class ForkSettingsBackupCoordinator {
    private weak var core: AppCore?
    private var task: Task<Void, Never>?

    init(core: AppCore) { self.core = core }

    func stop() { task?.cancel() }

    func run(openFolder: Bool) {
        guard task == nil, let core else { return }
        let folder = AppPaths.applicationSupport().appendingPathComponent("fork-settings-backups")
        task = Task { [weak self, weak core] in
            defer { self?.task = nil }
            guard let core else { return }
            do {
                if openFolder {
                    try await ForkSettingsBackupService.create(folder: folder)
                    try Task.checkCancellation()
                    guard NSWorkspace.shared.open(folder) else { throw CocoaError(.fileReadUnknown) }
                    return
                }
                guard let data = try await ForkSettingsBackupService.latest(folder: folder) else {
                    try Task.checkCancellation()
                    await core.showNotice(title: String(localized: "Restore Settings Backup"),
                        message: String(localized: "No settings backup was found."),
                        symbol: "clock.arrow.circlepath", tone: .neutral)
                    return
                }
                try Task.checkCancellation()
                let values = try ForkSettingsBackupEngine.decode(data)
                let confirmed = await core.confirm(title: String(localized: "Restore Settings Backup"),
                    message: String(localized: "Replace saved settings with the newest backup?"),
                    symbol: "clock.arrow.circlepath", confirmTitle: String(localized: "Restore"))
                try Task.checkCancellation()
                guard confirmed else { return }
                ForkSettingsBackupRestore.apply(values, to: .shared)
                core.showMessage(String(localized: "Settings restored."))
            } catch {
                guard !Task.isCancelled else { return }
                core.showMessage(String(localized: "Settings backup could not be opened or restored."), tone: .danger)
            }
        }
    }
}

extension ForkSettingsBackupCoordinator {
    static let restoreCommand = NotchcastCommand(slug: "restore-settings-backup",
        name: String(localized: "Restore Settings Backup"), sfSymbol: "clock.arrow.circlepath",
        run: { NotchcastCore.settingsBackupRestore?.run(openFolder: false) })
    static let openCommand = NotchcastCommand(slug: "open-settings-backup-folder",
        name: String(localized: "Open Settings Backup Folder"), sfSymbol: "folder",
        run: { NotchcastCore.settingsBackupRestore?.run(openFolder: true) })
}
