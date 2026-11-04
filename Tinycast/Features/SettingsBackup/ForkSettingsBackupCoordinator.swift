import AppKit

@MainActor
final class ForkSettingsBackupCoordinator {
    private var task: Task<Void, Never>?
    private var folderTask: Task<Void, Never>?
    private let folder: URL
    private let state: ForkSettingsBackupState
    private let confirm: () async -> Bool
    private let report: (Bool) -> Void
    private let missing: () async -> Void

    init(folder: URL = AppPaths.applicationSupport().appendingPathComponent("fork-settings-backups"),
         state: ForkSettingsBackupState = .live,
         confirm: @escaping () async -> Bool = {
             await AppCore.shared.confirm(title: String(localized: "Restore Settings Backup"),
                 message: String(localized: "Replace saved settings with the newest backup?"),
                 symbol: "clock.arrow.circlepath", confirmTitle: String(localized: "Restore"))
         },
         report: @escaping (Bool) -> Void = { success in
             if success {
                 AppCore.shared.showMessage(String(localized: "Settings restored."))
             } else {
                 AppCore.shared.showMessage(
                     String(localized: "Settings backup could not be opened or restored."), tone: .danger)
             }
         },
         missing: @escaping () async -> Void = {
             await AppCore.shared.showNotice(title: String(localized: "Restore Settings Backup"),
                 message: String(localized: "No settings backup was found."),
                 symbol: "clock.arrow.circlepath", tone: .neutral)
         }) {
        self.folder = folder
        self.state = state
        self.confirm = confirm
        self.report = report
        self.missing = missing
    }

    func stop() { task?.cancel(); folderTask?.cancel() }

    func settled() async { await task?.value }

    func openFolder() {
        guard folderTask == nil else { return }
        folderTask = Task { [weak self] in
            guard let self else { return }
            defer { folderTask = nil }
            do {
                try await ForkSettingsBackupService.create(folder: folder)
                try Task.checkCancellation()
                guard NSWorkspace.shared.open(folder) else { throw CocoaError(.fileReadUnknown) }
            } catch {
                if !Task.isCancelled { report(false) }
            }
        }
    }

    func restore() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            do {
                guard let data = try await ForkSettingsBackupService.latest(folder: folder) else {
                    try Task.checkCancellation()
                    await missing()
                    return
                }
                try Task.checkCancellation()
                let values = try ForkSettingsBackupEngine.decode(data)
                try state.validate(values)
                let confirmed = await confirm()
                try Task.checkCancellation()
                guard confirmed else { return }
                try state.validate(values)
                try state.apply(values)
                report(true)
            } catch {
                guard !Task.isCancelled else { return }
                report(false)
            }
        }
    }
}

extension ForkSettingsBackupCoordinator {
    nonisolated static let restoreCommand = NotchcastCommand(slug: "restore-settings-backup",
        name: String(localized: "Restore Settings Backup"), sfSymbol: "clock.arrow.circlepath",
        run: { NotchcastCore.settingsBackupRestore.restore() })
    nonisolated static let openCommand = NotchcastCommand(slug: "open-settings-backup-folder",
        name: String(localized: "Open Settings Backup Folder"), sfSymbol: "folder",
        run: { NotchcastCore.settingsBackupRestore.openFolder() })
}
