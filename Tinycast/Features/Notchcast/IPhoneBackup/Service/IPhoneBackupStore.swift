import Foundation
import Observation

/// Applies and restores the backup preference through a journal file written before the system.
@MainActor
@Observable
final class IPhoneBackupStore {
    private(set) var isApplied = false
    private(set) var backupsOff = false
    @ObservationIgnored private let context: NotchcastContext
    @ObservationIgnored private let system: IPhoneBackupSystem

    private struct WriteFailed: Error {}
    private struct JournalNotSaved: Error {}
    private struct JournalCorrupt: Error {}
    private struct StorageUnavailable: Error {}

    init(context: NotchcastContext, system: IPhoneBackupSystem) {
        self.context = context
        self.system = system
    }

    func refresh() {
        let current = try? system.read()
        isApplied = (try? loadJournal()).map { IPhoneBackupPolicy.isApplied($0, current: current) } ?? false
        backupsOff = (try? system.read()) == IPhoneBackupPolicy.disabled
    }

    /// Saves the previous value before writing; a failed capture turns the switch back off.
    func apply() {
        guard context.isEnabled(IPhoneBackupAddon.switchID) else { return }
        defer { refresh() }
        let journal: IPhoneBackupPolicy.Journal
        do {
            journal = try loadJournal()
        } catch {
            // The journal may hold a real capture: its bytes stay, and teardown restores only once it loads.
            context.defaults.set(true, forKey: IPhoneBackupPolicy.skipRestoreKey)
            turnOffFailed()
            return
        }
        let write: IPhoneBackupPolicy.Write
        do {
            let plan = IPhoneBackupPolicy.apply(current: try system.read(), journal: journal)
            try save(plan.journal)
            write = plan.write
        } catch {
            // The journal may be unverified, so the teardown this switch-off causes skips it until it loads.
            context.defaults.set(true, forKey: IPhoneBackupPolicy.skipRestoreKey)
            turnOffFailed()
            return
        }
        guard !system.write(write) else { return }
        // A failed sync can still leave the value written, so the capture rolls it back.
        if restore() { turnOffFailed() }
    }

    func decline() {
        context.preferences.set(IPhoneBackupAddon.switchID, on: false)
    }

    /// On but not in effect at launch: a question never answered, so the switch goes off unasked.
    func dropUnanswered() {
        let current: IPhoneBackupPolicy.Value?
        do { current = try system.read() } catch { return }
        guard let journal = try? loadJournal(), !IPhoneBackupPolicy.isApplied(journal, current: current) else { return }
        decline()
        if (try? clearJournal()) != nil {
            context.defaults.removeObject(forKey: IPhoneBackupPolicy.skipRestoreKey)
        }
    }

    /// A failed write or unavailable storage keeps the capture and, by default, the switch on, so switching off retries.
    /// A corrupt journal is kept and reported once; restores skip it quietly until it loads again.
    @discardableResult
    func restore(bounceOnFailure: Bool = true) -> Bool {
        defer { refresh() }
        let skipping = context.defaults.bool(forKey: IPhoneBackupPolicy.skipRestoreKey)
        do {
            try restoreJournal()
            context.defaults.removeObject(forKey: IPhoneBackupPolicy.skipRestoreKey)
            return true
        } catch is JournalCorrupt {
            guard !skipping else { return true }
            context.defaults.set(true, forKey: IPhoneBackupPolicy.skipRestoreKey)
            report(Self.restoreFailedText)
            return false
        } catch is StorageUnavailable where skipping {
            return true
        } catch {
            if bounceOnFailure { context.preferences.set(IPhoneBackupAddon.switchID, on: true) }
            report(Self.restoreFailedText)
            return false
        }
    }

    private func restoreJournal() throws {
        let journal = try loadJournal()
        if !journal.isEmpty, let write = IPhoneBackupPolicy.restore(journal: journal, current: try system.read()) {
            guard system.write(write) else { throw WriteFailed() }
        }
        try clearJournal()
    }

    private func clearJournal() throws {
        if FileManager.default.fileExists(atPath: journalFile.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: journalFile)
        }
        context.defaults.removeObject(forKey: IPhoneBackupPolicy.journalKey)
    }

    private func turnOffFailed() {
        context.preferences.set(IPhoneBackupAddon.switchID, on: false)
        report(Self.turnOffFailedText)
    }

    private static var restoreFailedText: String {
        String(localized: "Couldn’t restore iPhone auto backups", table: "NotchcastIPhoneBackup")
    }

    private static var turnOffFailedText: String {
        String(localized: "Couldn’t turn off iPhone auto backups", table: "NotchcastIPhoneBackup")
    }

    private var journalFile: URL { system.journalFolder.appending(path: IPhoneBackupPolicy.journalFile) }

    /// Absent is empty; unreadable storage is retryable; present data that is no journal, whatever its type, is corrupt.
    private func loadJournal() throws -> IPhoneBackupPolicy.Journal {
        let data: Data?
        if FileManager.default.fileExists(atPath: journalFile.path(percentEncoded: false)) {
            do { data = try system.readFile(journalFile) } catch { throw StorageUnavailable() }
        } else {
            let v1 = context.defaults.object(forKey: IPhoneBackupPolicy.journalKey)
            guard v1 == nil || v1 is Data else { throw JournalCorrupt() }
            data = v1 as? Data
        }
        do { return try IPhoneBackupPolicy.journal(from: data) } catch { throw JournalCorrupt() }
    }

    /// Read back before returning, so the system is written only once the capture is on disk.
    private func save(_ journal: IPhoneBackupPolicy.Journal) throws {
        try FileManager.default.createDirectory(at: system.journalFolder, withIntermediateDirectories: true)
        try IPhoneBackupPolicy.data(journal).write(to: journalFile, options: .atomic)
        guard try IPhoneBackupPolicy.journal(from: system.readFile(journalFile)) == journal else {
            throw JournalNotSaved()
        }
        context.defaults.removeObject(forKey: IPhoneBackupPolicy.skipRestoreKey)
    }

    private func report(_ text: String) {
        context.presenter.post(
            IslandNotice(id: IPhoneBackupAddon.switchID, symbol: "iphone", text: text, isFailure: true), onTap: nil)
    }
}
