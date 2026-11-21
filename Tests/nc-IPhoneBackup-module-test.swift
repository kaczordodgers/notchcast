// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/IPhoneBackupAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Service/IPhoneBackupModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Service/IPhoneBackupRecovery.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Service/IPhoneBackupStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Service/IPhoneBackupSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Service/IPhoneBackupSystem+Preferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/IPhoneBackup/Service/IPhoneBackupConfirmation.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import SwiftUI

// The shipped `live` and settings view are left out: only a scratch domain is ever read or written here.

struct IPhoneBackupSettingsView: View {
    init(store: IPhoneBackupStore) {}
    var body: some View { EmptyView() }
}

typealias Policy = IPhoneBackupPolicy

@MainActor
final class FakeSystem {
    var value: Policy.Value?
    var writes: [Policy.Write] = []
    var failingWrites = 0
    var failureMutates = false
    var reads = 0
    var failOnRead: Int?
    var readFails = false
    var failingReadBacks = 0
    var filesUnreadable = false
    var capturedAtWrite: [Bool] = []
}

@MainActor let fake = FakeSystem()

struct ReadFailed: Error {}

let scratch = FileManager.default.temporaryDirectory
    .appending(path: "nc-IPhoneBackup-test.\(UUID())", directoryHint: .isDirectory)
let journalFile = scratch.appending(path: Policy.journalFile)

func journalOnDisk() -> Data? { try? Data(contentsOf: journalFile) }

func plantJournal(_ data: Data) {
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    guard (try? data.write(to: journalFile)) != nil else { preconditionFailure("planting the journal failed") }
}

extension IPhoneBackupSystem {
    static let live = IPhoneBackupSystem(
        read: {
            fake.reads += 1
            if fake.readFails || fake.reads == fake.failOnRead { throw ReadFailed() }
            return fake.value
        },
        write: { write in
            fake.writes.append(write)
            fake.capturedAtWrite.append(journalOnDisk().map { !decoded($0).isEmpty } ?? false)
            let fails = fake.failingWrites > 0
            fake.failingWrites -= fails ? 1 : 0
            // The live writer sets the value before its sync can fail, so a failure may still land.
            guard !fails || fake.failureMutates else { return false }
            switch write {
            case .set(let value): fake.value = value
            case .delete: fake.value = nil
            }
            return !fails
        },
        journalFolder: scratch,
        readFile: { url in
            if MainActor.assumeIsolated({ fake.filesUnreadable }) { throw ReadFailed() }
            if MainActor.assumeIsolated({ fake.failingReadBacks > 0 }) {
                MainActor.assumeIsolated { fake.failingReadBacks -= 1 }
                throw ReadFailed()
            }
            return try Data(contentsOf: url)
        }
    )
}

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let suite: String
    let defaults: UserDefaults
    let presenter = FakePresenter()
    let controller: NotchcastController

    init(suite: String = "nc-IPhoneBackup-test.\(UUID())") {
        self.suite = suite
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [IPhoneBackupAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: presenter)
        controller.start()
    }

    var context: NotchcastContext { controller.context(forSwitch: IPhoneBackupAddon.switchID)! }
    var isOn: Bool { controller.preferences.isOn(IPhoneBackupAddon.switchID) }
    var hasModule: Bool { context.module(IPhoneBackupModule.self) != nil }
    var journal: Policy.Journal { decoded(journalOnDisk() ?? defaults.data(forKey: Policy.journalKey)) }

    /// The row's own store, built as the shipped settings row builds it.
    func store() -> IPhoneBackupStore { IPhoneBackupStore(context: context, system: .live) }

    /// The row's question as the shipped view drives it, after its `onAppear`.
    func ask() -> IPhoneBackupConfirmation {
        let confirmation = IPhoneBackupConfirmation(store: store())
        confirmation.appear()
        return confirmation
    }

    func set(_ on: Bool) async {
        controller.preferences.set(IPhoneBackupAddon.switchID, on: on)
        await drain()
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

func decoded(_ data: Data?) -> Policy.Journal {
    guard let journal = try? Policy.journal(from: data) else { preconditionFailure("journal unreadable") }
    return journal
}

/// Every hop here lands on the main actor, so yielding runs them in order.
@MainActor func drain() async { for _ in 0..<10 { await Task.yield() } }

@MainActor
func reset(_ value: Policy.Value?) {
    fake.value = value
    fake.writes = []
    fake.failingWrites = 0
    fake.failureMutates = false
    fake.reads = 0
    fake.failOnRead = nil
    fake.readFails = false
    fake.failingReadBacks = 0
    fake.filesUnreadable = false
    fake.capturedAtWrite = []
    try? FileManager.default.removeItem(at: scratch)
}

/// v1's `TypingPreferencePlan` encoding, as Damian's v1 build left it in `iPhoneBackupTweaksPlans`.
let v1Journal = """
    {"automatic-backups":{"entries":[{"write":{"preference":{"domain":"com.apple.AMPDevicesClient",\
    "key":"AutomaticDeviceBackupsDisabled"},"value":{"bool":{"_0":true}}},"previous":{"integer":{"_0":0}}}]}}
    """

@MainActor
func read(_ system: IPhoneBackupSystem) -> Policy.Value? {
    do { return try system.read() } catch { preconditionFailure("the preference read threw") }
}

let hostFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences/ByHost")

/// The run's sweep skips ByHost, so the run removes its own domain's host plist and nothing else.
func removeHostFiles(_ domain: String) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: hostFolder.path(percentEncoded: false))) ?? []
    for name in names where name.hasPrefix(domain + ".") {
        try? FileManager.default.removeItem(at: hostFolder.appending(path: name))
    }
}

/// Capture reads the source restore writes: a value inherited from another source reads as absent.
@MainActor
func preferenceSource() {
    let domain = "nc-IPhoneBackup-test.\(UUID())"
    let otherRun = hostFolder.appending(path: "nc-IPhoneBackup-test.\(UUID()).other-run.plist")
    // A fresh home has no ByHost folder until the first host preference is written.
    try? FileManager.default.createDirectory(at: hostFolder, withIntermediateDirectories: true)
    precondition(
        FileManager.default.createFile(atPath: otherRun.path(percentEncoded: false), contents: nil),
        "planting another run's file failed")
    let key = Policy.key as CFString
    let system = IPhoneBackupSystem.preferences(domain: domain, journalFolder: scratch)
    CFPreferencesSetValue(key, kCFBooleanTrue, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    defer {
        // The daemon forgets both values before the host plist goes, so it has nothing left to write back.
        for host in [kCFPreferencesCurrentHost, kCFPreferencesAnyHost] {
            CFPreferencesSetValue(key, nil, domain as CFString, kCFPreferencesCurrentUser, host)
            CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, host)
        }
        removeHostFiles(domain)
        precondition(FileManager.default.fileExists(atPath: otherRun.path(percentEncoded: false)), "another run's file stays")
        try? FileManager.default.removeItem(at: otherRun)
    }
    precondition(CFPreferencesCopyAppValue(key, domain as CFString) != nil, "the app search sees the host value")
    precondition(read(system) == nil, "an inherited value is not the user's: capture reads absent")
    for value: Policy.Value in [.bool(true), .integer(0), .real(1.5), .string("x")] {
        precondition(system.write(.set(value)) && read(system) == value, "\(value) round-trips")
    }
    precondition(system.write(.delete) && read(system) == nil, "delete removes the user's value")
}

@main
enum IPhoneBackupModuleTests {
    @MainActor
    static func main() async {
        // Write plan: on writes disabled = true and captures the prior value; off writes it back or deletes.
        let absent = Policy.apply(current: nil, journal: [:])
        precondition(absent.write == .set(.bool(true)), "on writes AutomaticDeviceBackupsDisabled = true")
        precondition(Policy.restore(journal: absent.journal, current: .bool(true)) == .delete, "absent → delete")
        let prior = Policy.apply(current: .bool(false), journal: [:])
        precondition(Policy.restore(journal: prior.journal, current: .bool(true)) == .set(.bool(false)), "prior")
        let again = Policy.apply(current: .bool(true), journal: prior.journal)
        precondition(again.journal == prior.journal, "a second apply keeps the first capture")
        precondition(Policy.restore(journal: [:], current: .bool(true)) == nil, "no capture → no write")
        precondition(
            Policy.restore(journal: prior.journal, current: .bool(false)) == nil
                && Policy.restore(journal: prior.journal, current: nil) == nil, "a changed value is not ours to restore")
        let recaptured = Policy.apply(current: .bool(false), journal: absent.journal)
        precondition(
            Policy.restore(journal: recaptured.journal, current: .bool(true)) == .set(.bool(false)),
            "a capture the system no longer holds is replaced by the current value")
        let entry = absent.journal[Policy.planID]!.entries[0].write.preference
        precondition(entry.domain == "com.apple.AMPDevicesClient", "the domain v1 wrote")
        precondition(entry.key == "AutomaticDeviceBackupsDisabled", "the key v1 wrote")

        // v1 journal: Damian's capture decodes and restores; ours round-trips.
        let v1 = decoded(Data(v1Journal.utf8))
        precondition(Policy.isApplied(v1, current: .bool(true)), "a v1 capture counts as applied")
        precondition(Policy.restore(journal: v1, current: .bool(true)) == .set(.integer(0)), "v1 prior restores")
        precondition(decoded(try? Policy.data(prior.journal)) == prior.journal, "round trip")
        precondition((try? Policy.journal(from: Data("[1]".utf8))) == nil, "an unreadable journal throws")

        // Switch on: nothing is written until the row's question is accepted.
        reset(.bool(false))
        var rig = Rig()
        precondition(!rig.isOn && !rig.hasModule, "off by default")
        await rig.set(true)
        precondition(rig.hasModule, "the module runs while the switch is on")
        precondition(fake.writes.isEmpty, "turning the switch on writes nothing by itself")
        let store = rig.store()
        var ask = IPhoneBackupConfirmation(store: store)
        ask.appear()
        precondition(ask.isPresented && !store.backupsOff, "the row asks: nothing applied yet")
        precondition(rig.isOn && fake.writes.isEmpty, "asking writes nothing")
        ask.accept()
        precondition(!ask.isPresented && rig.isOn, "accept: the question closes, the switch stays on")
        precondition(fake.writes == [.set(.bool(true))], "accept writes disabled = true")
        precondition(fake.capturedAtWrite == [true], "the capture is on disk before the system write")
        precondition(rig.defaults.data(forKey: Policy.journalKey) == nil, "the capture lives in the file")
        precondition(store.isApplied && store.backupsOff, "the row reads backups off")
        precondition(!rig.journal.isEmpty, "the capture is saved")
        ask.setPresented(false)
        await drain()
        precondition(rig.isOn && fake.writes.count == 1, "the dismissal after accept declines nothing")
        precondition(!rig.ask().isPresented, "once applied, the row asks no more")

        // Quitting stops the module with the switch on: backups stay off, the capture stays.
        rig.controller.stop()
        precondition(fake.writes.count == 1, "quitting writes nothing")
        precondition(!rig.journal.isEmpty, "quitting keeps the capture")
        let kept = rig.suite
        rig = Rig(suite: kept)
        precondition(rig.isOn && rig.hasModule && fake.writes.count == 1, "relaunch keeps the switch, writes nothing")

        // Switch off: the prior value comes back and the capture goes.
        await rig.set(false)
        precondition(!rig.hasModule, "the module stops")
        precondition(fake.writes == [.set(.bool(true)), .set(.bool(false))], "off restores the prior value")
        precondition(rig.journal.isEmpty && journalOnDisk() == nil, "the journal file is deleted once restored")
        rig.finish()

        // A key that was absent is deleted again.
        reset(nil)
        rig = Rig()
        await rig.set(true)
        rig.ask().accept()
        await rig.set(false)
        precondition(fake.writes == [.set(.bool(true)), .delete] && fake.value == nil, "absent key is deleted")
        rig.finish()

        // Damian's v1 state: switch on and a v1 capture; no question, and off restores the v1 prior.
        reset(.bool(true))
        let v1Suite = "nc-IPhoneBackup-test.\(UUID())"
        UserDefaults(suiteName: v1Suite)!.set(true, forKey: IPhoneBackupAddon.switchID)
        UserDefaults(suiteName: v1Suite)!.set(Data(v1Journal.utf8), forKey: Policy.journalKey)
        rig = Rig(suite: v1Suite)
        precondition(rig.isOn && !rig.ask().isPresented && fake.writes.isEmpty, "v1 state needs no question")
        await rig.set(false)
        precondition(fake.writes == [.set(.integer(0))], "off restores the value v1 captured")
        precondition(rig.defaults.data(forKey: Policy.journalKey) == nil, "the v1 capture goes once restored")
        precondition(rig.journal.isEmpty && !rig.isOn, "after the v1 restore nothing is applied")
        rig.finish()

        // The journal cannot be written: nothing reaches the system, the switch goes off, one notice.
        reset(.bool(false))
        FileManager.default.createFile(atPath: scratch.path(percentEncoded: false), contents: nil)
        rig = Rig()
        await rig.set(true)
        rig.ask().accept()
        await drain()
        precondition(fake.writes.isEmpty && fake.value == .bool(false), "unsaved journal: no system write")
        precondition(!rig.isOn && rig.presenter.posts.count == 1, "unsaved journal: switch off, one notice")
        try? FileManager.default.removeItem(at: scratch)
        rig.finish()

        // Cancel turns the switch back off and writes nothing; a late accept writes nothing either.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        ask = rig.ask()
        ask.cancel()
        await drain()
        precondition(!ask.isPresented, "cancel closes the question")
        precondition(!rig.isOn && !rig.hasModule && fake.writes.isEmpty, "cancel: switch off, nothing written")
        ask.accept()
        precondition(fake.writes.isEmpty, "an accept after the switch went off writes nothing")
        rig.finish()

        // A dismissal without an answer is a cancel.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        ask = rig.ask()
        ask.setPresented(false)
        precondition(rig.isOn && fake.writes.isEmpty, "the dismissal decides one turn later")
        await drain()
        precondition(!rig.isOn && !rig.hasModule && fake.writes.isEmpty, "dismiss: switch off, nothing written")
        rig.finish()

        // SwiftUI clearing the binding before the accept action still applies.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        ask = rig.ask()
        ask.setPresented(false)
        ask.accept()
        await drain()
        precondition(rig.isOn && fake.writes == [.set(.bool(true))], "binding first, then accept: applied")
        rig.finish()

        // A failed sync that still wrote: the capture rolls the value back, the switch goes off.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        (fake.failingWrites, fake.failureMutates) = (1, true)
        rig.ask().accept()
        await drain()
        precondition(fake.writes == [.set(.bool(true)), .set(.bool(false))], "failed apply rolls back from the capture")
        precondition(!rig.isOn && fake.value == .bool(false), "failed apply: switch off, value back")
        precondition(rig.presenter.posts.last?.isFailure == true, "failed apply is reported")
        precondition(rig.journal.isEmpty, "a rolled-back apply leaves no capture")
        rig.finish()

        // The rollback fails too: the switch stays on with the capture, so switching off retries.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        (fake.failingWrites, fake.failureMutates) = (2, true)
        rig.ask().accept()
        await drain()
        precondition(rig.isOn && rig.hasModule, "failed rollback: the switch stays on")
        precondition(!rig.journal.isEmpty, "failed rollback keeps the capture")
        precondition(rig.presenter.posts.count == 1, "failed rollback is reported once")
        await rig.set(false)
        precondition(!rig.isOn && fake.value == .bool(false) && rig.journal.isEmpty, "switching off retries the rollback")
        rig.finish()

        // An unreadable key at capture writes nothing and turns the switch off.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        fake.readFails = true
        rig.ask().accept()
        await drain()
        precondition(fake.writes.isEmpty && !rig.isOn, "unreadable read: nothing written, switch off")
        rig.finish()

        // An unreadable journal can hide a real capture: accept writes nothing, keeps the bytes, switches off.
        for planted in ["file", "v1 key"] {
            reset(.bool(false))
            rig = Rig()
            await rig.set(true)
            let garbage = Data("[1]".utf8)
            if planted == "file" { plantJournal(garbage) } else { rig.defaults.set(garbage, forKey: Policy.journalKey) }
            rig.ask().accept()
            await drain()
            precondition(fake.writes.isEmpty && !rig.isOn, "unreadable \(planted): nothing written, switch off")
            precondition(rig.presenter.posts.count == 1, "unreadable \(planted): exactly one notice")
            precondition(rig.presenter.posts.allSatisfy { $0.isFailure && $0.seconds == nil }, "the notice is a bare failure")
            precondition(rig.defaults.bool(forKey: Policy.skipRestoreKey), "unreadable \(planted): restores are skipped")
            let kept = planted == "file" ? journalOnDisk() : rig.defaults.data(forKey: Policy.journalKey)
            precondition(kept == Data("[1]".utf8), "unreadable \(planted) is kept")
            rig.finish()
        }

        // A failed restore turns the switch back on and keeps the capture, so switching off retries.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        rig.ask().accept()
        fake.failingWrites = 1
        await rig.set(false)
        await drain()
        precondition(rig.isOn && rig.hasModule, "failed restore: the switch is back on, the row stays")
        precondition(!rig.journal.isEmpty, "failed restore keeps the capture")
        precondition(rig.presenter.posts.last?.isFailure == true, "failed restore is reported")
        precondition(fake.value == .bool(true) && !rig.ask().isPresented, "backups stay off, no new question")
        await rig.set(false)
        precondition(!rig.isOn && fake.value == .bool(false), "the retry restores the prior value")
        precondition(rig.journal.isEmpty, "the retry drops the capture")
        rig.finish()

        // A value the user changed after the apply is kept: switching off restores nothing over it.
        reset(.bool(true))
        rig = Rig()
        await rig.set(true)
        rig.ask().accept()
        fake.value = .bool(false)
        await rig.set(false)
        precondition(!rig.isOn && fake.value == .bool(false), "an external change survives the switch-off")
        precondition(fake.writes == [.set(.bool(true))], "no restore write over a later change")
        precondition(rig.journal.isEmpty && journalOnDisk() == nil, "the stale capture is dropped")
        rig.finish()

        // A transient read failure at restore stays retryable: no marker, switch back on, then it recovers.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        rig.ask().accept()
        fake.failingReadBacks = 1
        await rig.set(false)
        await drain()
        precondition(rig.isOn && !rig.journal.isEmpty, "transient read failure: switch back on, capture kept")
        precondition(!rig.defaults.bool(forKey: Policy.skipRestoreKey), "a transient failure sets no marker")
        precondition(rig.presenter.posts.count == 1, "transient read failure is reported once")
        await rig.set(false)
        precondition(!rig.isOn && fake.value == .bool(false) && rig.journal.isEmpty, "the next switch-off restores")
        rig.finish()

        // A corrupt journal at restore: kept and reported once, the switch stays off, nothing bounces it on.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        rig.ask().accept()
        let goodJournal = journalOnDisk()!
        plantJournal(Data("[1]".utf8))
        await rig.set(false)
        await drain()
        precondition(!rig.isOn && fake.value == .bool(true), "corrupt journal at restore: the switch stays off")
        precondition(journalOnDisk() == Data("[1]".utf8), "the journal is kept")
        precondition(rig.presenter.posts.count == 1, "corrupt journal at restore is reported once")
        precondition(rig.defaults.bool(forKey: Policy.skipRestoreKey), "a persistent marker skips later restores")
        rig.controller.stop()
        let markedSuite = rig.suite
        rig = Rig(suite: markedSuite)
        precondition(!rig.isOn && rig.presenter.posts.isEmpty && fake.writes.count == 1, "the marker survives a relaunch quietly")
        await rig.set(true)
        await rig.set(false)
        precondition(!rig.isOn && fake.writes.count == 1, "switching on and off again restores nothing and stays off")
        plantJournal(goodJournal)
        rig.controller.stop()
        rig = Rig(suite: markedSuite)
        precondition(fake.value == .bool(false) && fake.writes.last == .set(.bool(false)), "a journal that loads again restores")
        precondition(!rig.defaults.bool(forKey: Policy.skipRestoreKey) && journalOnDisk() == nil, "and clears the skip")
        rig.finish()

        // A read-back that fails after the atomic write: no system write, the leftover journal is no applied change.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        fake.filesUnreadable = true
        rig.ask().accept()
        await drain()
        fake.filesUnreadable = false
        precondition(!rig.isOn && rig.presenter.posts.last?.isFailure == true, "failed read-back: switch off, reported")
        precondition(fake.writes.isEmpty && fake.value == .bool(false), "failed read-back: no system write at all")
        precondition(journalOnDisk() != nil, "the unverified journal is still there")
        let keptSuite = rig.suite
        await rig.set(true)
        ask = rig.ask()
        precondition(ask.isPresented, "a leftover capture is not an applied change: ask again")
        ask.accept()
        await drain()
        precondition(rig.isOn && fake.writes == [.set(.bool(true))], "the confirmed retry applies")
        precondition(!rig.defaults.bool(forKey: Policy.skipRestoreKey), "a verified save clears the skip")
        rig.controller.stop()
        rig = Rig(suite: keptSuite)
        precondition(rig.isOn && !rig.ask().isPresented, "relaunch: applied, no question")
        await rig.set(false)
        precondition(fake.value == .bool(false) && rig.journal.isEmpty, "off restores the value from before the retry")
        rig.finish()

        // A switch-off whose restore never ran is reconciled at the next launch, with the switch off.
        for transient in [false, true] {
            reset(.bool(false))
            rig = Rig()
            await rig.set(true)
            rig.ask().accept()
            rig.controller.stop()
            let crashed = rig.suite
            UserDefaults(suiteName: crashed)!.set(false, forKey: IPhoneBackupAddon.switchID)
            precondition(fake.value == .bool(true) && !rig.journal.isEmpty, "crash: off with an unrestored capture")
            fake.failingReadBacks = transient ? 1 : 0
            rig = Rig(suite: crashed)
            if transient {
                precondition(!rig.isOn && fake.value == .bool(true), "transient failure at launch: switch stays off")
                precondition(rig.presenter.posts.count == 1 && !rig.journal.isEmpty, "reported once, capture kept")
                rig.controller.stop()
                rig = Rig(suite: crashed)
            }
            precondition(!rig.isOn && fake.value == .bool(false) && rig.journal.isEmpty, "launch restores the pending capture")
            rig.finish()
        }

        for captured in [false, true] {
            reset(.bool(false))
            let leftOn = "nc-IPhoneBackup-test.\(UUID())"
            UserDefaults(suiteName: leftOn)!.set(true, forKey: IPhoneBackupAddon.switchID)
            if captured { plantJournal(Data(v1Journal.utf8)) }
            fake.failOnRead = 2
            rig = Rig(suite: leftOn)
            precondition(fake.reads == 1, "stale switch recovery uses only the first system read")
            precondition(!rig.isOn && !rig.hasModule, "left on, not applied: the switch is off at launch")
            precondition(fake.writes.isEmpty && rig.presenter.posts.isEmpty, "turned off quietly, nothing written")
            precondition(rig.journal.isEmpty && journalOnDisk() == nil, "a capture the system no longer holds goes")
            rig.finish()
        }

        reset(.bool(true))
        let unreadable = "nc-IPhoneBackup-test.\(UUID())"
        UserDefaults(suiteName: unreadable)!.set(true, forKey: IPhoneBackupAddon.switchID)
        let captured = Data(v1Journal.utf8)
        plantJournal(captured)
        fake.failOnRead = 1
        rig = Rig(suite: unreadable)
        precondition(rig.isOn && fake.writes.isEmpty, "a failed read at launch decides nothing")
        precondition(journalOnDisk() == captured, "a failed first read keeps the journal")
        rig.finish()

        // A corrupt journal at launch keeps the switch as it was and the journal's bytes.
        reset(.bool(false))
        let corrupt = "nc-IPhoneBackup-test.\(UUID())"
        UserDefaults(suiteName: corrupt)!.set(true, forKey: IPhoneBackupAddon.switchID)
        let garbage = Data("not a journal".utf8)
        plantJournal(garbage)
        rig = Rig(suite: corrupt)
        precondition(rig.isOn && fake.writes.isEmpty, "a corrupt journal at launch decides nothing")
        precondition(journalOnDisk() == garbage, "a corrupt journal at launch is kept")
        rig.finish()

        // A v1 journal of the wrong type is corrupt, not absent: nothing is written, the value is kept.
        reset(.bool(false))
        rig = Rig()
        await rig.set(true)
        rig.defaults.set("not data", forKey: Policy.journalKey)
        rig.ask().accept()
        await drain()
        precondition(fake.writes.isEmpty && !rig.isOn, "string v1 journal: nothing written, switch off")
        precondition(rig.presenter.posts.count == 1, "string v1 journal: exactly one notice")
        precondition(rig.defaults.string(forKey: Policy.journalKey) == "not data", "string v1 journal is kept")
        rig.finish()

        preferenceSource()
        reset(nil)

        print("nc-IPhoneBackup-module-test: OK")
    }
}
