import AppKit
import Observation

@MainActor
@Observable final class ForkSettingsBackupCoordinator {
    private(set) var copies: [ForkSettingsBackupService.Copy] = []
    private(set) var choosing = false
    private var task: Task<Void, Never>?
    private var folderTask: Task<Void, Never>?
    private let folder: URL
    private let state: ForkSettingsBackupState
    private let confirm: () async -> Bool
    private let report: (Bool) -> Void

    init(folder: URL = AppPaths.applicationSupport().appendingPathComponent("fork-settings-backups"),
         state: ForkSettingsBackupState = .live,
         confirm: @escaping () async -> Bool = {
             await AppCore.shared.confirm(title: String(localized: "Restore Settings Backup", table: "Notchcast"),
                 message: String(localized: "Replace saved settings with the selected backup?", table: "Notchcast"),
                 symbol: "clock.arrow.circlepath", confirmTitle: String(localized: "Restore", table: "Notchcast"))
         },
         report: @escaping (Bool) -> Void = { success in
             if success {
                 AppCore.shared.showMessage(String(localized: "Settings restored.", table: "Notchcast"))
             } else {
                 AppCore.shared.showMessage(
                     String(localized: "Settings backup could not be opened or restored.", table: "Notchcast"), tone: .danger)
             }
         }) {
        self.folder = folder
        self.state = state
        self.confirm = confirm
        self.report = report
    }

    func stop() { cancelChoosing(); folderTask?.cancel() }

    func cancelChoosing() {
        choosing = false
        task?.cancel()
    }

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
                let result = try await ForkSettingsBackupService.copies(folder: folder)
                try Task.checkCancellation()
                copies = result
                choosing = true
            } catch {
                if !Task.isCancelled { report(false) }
            }
        }
    }

    func restore(name: String) {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil; choosing = false }
            do {
                let data = try await ForkSettingsBackupService.read(folder: folder, name: name)
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
        name: String(localized: "Restore Settings Backup", table: "Notchcast"), sfSymbol: "clock.arrow.circlepath", feature: .settingsBackup,
        run: {
            SettingsActionCommands.show(NotchcastSettingsModule.module(of: .settingsBackup).tab, .settingsBackup)
            NotchcastCore.settingsBackupRestore.restore()
        })
    nonisolated static let openCommand = NotchcastCommand(slug: "open-settings-backup-folder",
        name: String(localized: "Open Settings Backup Folder", table: "Notchcast"), sfSymbol: "folder", feature: .settingsBackup,
        run: { NotchcastCore.settingsBackupRestore.openFolder() })
}
