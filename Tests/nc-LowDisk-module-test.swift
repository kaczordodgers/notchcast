// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/LowDiskAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/Service/LowDiskModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import SwiftUI

// The shipped disk read and settings view are left out: these stand in, so `makeModule` runs as shipped.

struct LowDiskSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

struct ReadFailed: Error {}

@MainActor
final class FakeDisk {
    var free: Int64 = gb(50)
    var fails = false
    var displayAsleep = false
}

@MainActor let disk = FakeDisk()

func gb(_ value: Int) -> Int64 { Int64(value) * 1_000_000_000 }

extension LowDiskModule {
    static func readStartupDisk() async throws -> Int64 {
        if disk.fails { throw ReadFailed() }
        return disk.free
    }

    static func isMainDisplayAsleep() -> Bool { disk.displayAsleep }
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
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    var statuses: [IslandStatus?] = []
    var statusTap: (@MainActor () -> Void)?
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        precondition(id == "lowDisk")
        statuses.append(status)
        statusTap = onTap
    }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// One app launch on a suite; a second Rig on the same suite is the next launch.
@MainActor
final class Rig {
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController

    init(suite: String, on: Bool?) {
        defaults = UserDefaults(suiteName: suite)!
        if let on { defaults.set(on, forKey: "lowDiskWarning") }
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [LowDiskAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(), presenter: presenter)
        controller.start()
    }

    var module: LowDiskModule? { controller.context(forSwitch: "lowDiskWarning")?.module(LowDiskModule.self) }

    func threshold(_ gigabytes: Int) { defaults.set(gigabytes, forKey: LowDiskPolicy.thresholdKey) }

    /// Awaits the check start() fired, else a new one, so no reading is ever raced.
    func settle() async { await module?.checking?.value }

    func check() async { await module?.check()?.value }

    var warnings: [IslandNotice] { presenter.posts.filter { $0.text.hasPrefix("Low disk space: ") } }
}

@main
@MainActor
enum LowDiskModuleTests {
    static func main() async {
        descriptor()
        policy()
        await warnsOnceAndRearms()
        await waitsForTheDisplay()
        await command()
        await statusTap()
        print("PASS nc-LowDisk-module-test")
    }

    static func descriptor() {
        let only = LowDiskAddon.switches
        precondition(only.map(\.id) == ["lowDiskWarning"], "v1 switch id")
        precondition(only[0].defaultEnabled == false, "off by default")
        precondition(only[0].category == .power, "Power category")
        precondition(LowDiskAddon.commands.map(\.slug) == ["check-disk-space"], "v1 command slug")
        precondition(LowDiskAddon.commands[0].switchID == "lowDiskWarning", "the command rides the switch")
        precondition(LowDiskAddon.settings.map(\.switchID) == ["lowDiskWarning"], "the threshold sits under it")
        precondition(LowDiskPolicy.checkInterval == .seconds(1800), "every 30 minutes, no tighter loop")
    }

    static let lowDiskStatus = IslandStatus(
        id: "lowDisk", symbol: "internaldrive", text: nil, label: "Low disk space", tone: nil)

    static func policy() {
        precondition(LowDiskPolicy.thresholdGB(stored: nil) == 10, "10 GB by default")
        precondition(LowDiskPolicy.thresholdGB(stored: 0) == 1 && LowDiskPolicy.thresholdGB(stored: 9999) == 500,
                     "an out-of-range threshold clamps")
        precondition(LowDiskPolicy.bytes(gigabytes: 10) == 10_000_000_000, "decimal gigabytes")

        var policy = LowDiskPolicy()
        precondition(policy.status == nil, "no status before warning")
        let readings: [(Int, Bool)] = [(50, false), (9, true), (8, false), (5, false), (10, false), (9, false),
                                       (11, false), (9, true), (12, false), (10, false), (3, true)]
        let showsStatus = [false, true, true, true, true, true, false, true, false, false, true]
        for (index, (free, warns)) in readings.enumerated() {
            precondition(policy.shouldWarn(free: gb(free), thresholdGB: 10, displayAsleep: false) == warns,
                         "reading \(index): \(free) GB")
            precondition(policy.status == (showsStatus[index] ? lowDiskStatus : nil), "status at reading \(index)")
        }
        precondition(policy.hasWarned, "a warning stays spent while below")
        precondition(!policy.shouldWarn(free: gb(10) + 900_000_000, thresholdGB: 10, displayAsleep: false))
        precondition(policy.status == lowDiskStatus, "10.9 GB is still inside the margin")
        precondition(!policy.shouldWarn(free: -1, thresholdGB: 10, displayAsleep: false) && policy.hasWarned,
                     "no reading changes nothing")
        precondition(policy.status == lowDiskStatus, "a negative reading leaves the status")
        precondition(!policy.shouldWarn(free: gb(110), thresholdGB: 100, displayAsleep: false))
        precondition(policy.status == nil, "110 GB re-arms at a threshold of 100")
        precondition(LowDiskPolicy.rearmBytes(thresholdGB: 10) == gb(11), "a small threshold re-arms 1 GB above")
        precondition(LowDiskPolicy.rearmBytes(thresholdGB: 100) == gb(110), "a large one a tenth above")

        var asleep = LowDiskPolicy()
        precondition(!asleep.shouldWarn(free: gb(3), thresholdGB: 10, displayAsleep: true) && !asleep.hasWarned,
                     "a sleeping display keeps the warning unspent")
        precondition(asleep.status == nil, "a sleeping display gets no status")
        precondition(asleep.shouldWarn(free: gb(3), thresholdGB: 10, displayAsleep: false), "so it warns once awake")
        precondition(asleep.status == lowDiskStatus, "the status appears with the warning")

        var raised = LowDiskPolicy()
        func warns(_ thresholdGB: Int) -> Bool {
            raised.shouldWarn(free: gb(50), thresholdGB: thresholdGB, displayAsleep: false)
        }
        precondition(!warns(10), "above the default")
        precondition(warns(60), "raising the threshold over free space warns")
        precondition(raised.status == lowDiskStatus, "raising the threshold shows the status")
        precondition(!warns(60), "and only once")
        precondition(!warns(40), "lowering it under free space re-arms")
        precondition(raised.status == nil, "lowering the threshold past the margin clears the status")
        precondition(warns(60), "so raising it again warns again")
    }

    static func warnsOnceAndRearms() async {
        let suite = "nc-LowDisk-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        disk.free = gb(50)
        disk.fails = false

        var rig = Rig(suite: suite, on: nil)
        precondition(rig.module == nil, "default off: no module")
        rig.controller.stop()

        rig = Rig(suite: suite, on: true)
        precondition(rig.module?.isRunning == true, "a stored true starts the module")
        await rig.settle()
        precondition(rig.presenter.posts.isEmpty, "50 GB free is above 10 GB: no warning")
        precondition(rig.presenter.statuses.isEmpty, "no status above the threshold")

        rig.threshold(60)
        await rig.check()
        await rig.check()
        await rig.check()
        precondition(rig.warnings.count == 1, "one warning, never repeated: \(rig.presenter.posts.map(\.text))")
        let warning = rig.warnings[0]
        precondition(warning.text == LowDiskPolicy.warning(free: gb(50)), "the warning names free space")
        precondition(warning.id == LowDiskModule.noticeID && warning.symbol == "internaldrive", "its id and glyph")
        precondition(warning.isFailure && warning.progress == nil, "a tinted message, not progress")
        precondition(rig.presenter.statuses == [lowDiskStatus], "three checks post one status")
        await switchOff(rig)
        precondition(rig.presenter.statuses == [lowDiskStatus, nil] && rig.presenter.statusTap == nil,
                     "switching off clears a posted status once and removes its tap")
        precondition(rig.presenter.ends == [LowDiskModule.noticeID], "switching off ends its notice")
        precondition(rig.module == nil, "and drops the module")
        rig.controller.stop()

        rig = Rig(suite: suite, on: true)
        precondition(rig.presenter.statuses.isEmpty, "the stored flag alone posts nothing")
        await rig.settle()
        await rig.check()
        precondition(rig.presenter.posts.isEmpty, "a relaunch still below does not warn again")
        precondition(rig.presenter.statuses == [lowDiskStatus], "the first reading restores the status")

        disk.fails = true
        await rig.check()
        precondition(rig.presenter.posts.isEmpty, "a failed read changes nothing")
        precondition(rig.presenter.statuses == [lowDiskStatus], "a failed read leaves the status")
        disk.fails = false

        disk.free = gb(60)
        await rig.check()
        precondition(rig.defaults.bool(forKey: LowDiskPolicy.warnedKey), "back at the threshold is not yet re-armed")
        precondition(rig.presenter.statuses == [lowDiskStatus], "the status holds at the threshold")
        disk.free = gb(66)
        await rig.check()
        precondition(rig.presenter.posts.isEmpty, "a tenth above the threshold: re-armed, no warning")
        precondition(!rig.defaults.bool(forKey: LowDiskPolicy.warnedKey), "the re-arm is stored")
        precondition(rig.presenter.statuses == [lowDiskStatus, nil], "the status clears at the re-arm mark")
        disk.free = gb(59)
        await rig.check()
        await rig.check()
        precondition(rig.warnings.count == 1, "dropping again warns once more")
        precondition(rig.warnings[0].text == LowDiskPolicy.warning(free: gb(59)), "with the new reading")
        precondition(rig.presenter.statuses == [lowDiskStatus, nil, lowDiskStatus], "a new drop restores the status")
        rig.controller.stop()
        precondition(rig.module == nil, "stopped")

        disk.free = gb(66)
        rig = Rig(suite: suite, on: true)
        await rig.settle()
        precondition(rig.presenter.statuses.isEmpty, "a recovered disk never flashes the stored status on launch")
        await switchOff(rig)
        precondition(rig.presenter.statuses.isEmpty, "switching off with no status sends no clear")
        rig.controller.stop()
    }

    static func switchOff(_ rig: Rig) async {
        await withCheckedContinuation { continuation in
            rig.controller.onCommandsChanged = { _ in continuation.resume() }
            rig.controller.preferences.set("lowDiskWarning", on: false)
        }
        rig.controller.onCommandsChanged = nil
        precondition(rig.module == nil, "the switch stopped the module")
    }

    static func waitsForTheDisplay() async {
        let suite = "nc-LowDisk-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        disk.free = gb(5)
        disk.fails = false
        disk.displayAsleep = true
        defer { disk.displayAsleep = false }

        var rig = Rig(suite: suite, on: true)
        await rig.settle()
        await rig.check()
        precondition(rig.presenter.posts.isEmpty, "display asleep: nobody would see the warning")
        precondition(rig.presenter.statuses.isEmpty, "display asleep: no status")
        precondition(!rig.defaults.bool(forKey: LowDiskPolicy.warnedKey), "so it is not spent")
        rig.controller.stop()

        rig = Rig(suite: suite, on: true)
        await rig.settle()
        precondition(rig.presenter.posts.isEmpty, "a relaunch with the display still asleep stays quiet")
        disk.displayAsleep = false
        await rig.check()
        await rig.check()
        precondition(rig.warnings.count == 1, "display awake: the warning shows, once")
        precondition(rig.presenter.statuses == [lowDiskStatus], "display awake: the status appears")
        rig.controller.stop()

        disk.displayAsleep = true
        rig = Rig(suite: suite, on: true)
        await rig.settle()
        precondition(rig.presenter.statuses.isEmpty, "a saved warning waits for the first awake reading")
        disk.displayAsleep = false
        await rig.check()
        precondition(rig.presenter.statuses == [lowDiskStatus] && rig.warnings.isEmpty,
                     "waking restores the status without repeating the warning")
        rig.controller.stop()
    }

    static func command() async {
        let suite = "nc-LowDisk-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        disk.free = gb(50)
        disk.fails = false

        var rig = Rig(suite: suite, on: false)
        precondition(!rig.controller.run(entryID: "command:nc-check-disk-space"), "off: the command is not live")
        rig.controller.stop()

        rig = Rig(suite: suite, on: true)
        await rig.settle()
        guard let module = rig.module else { preconditionFailure("module") }
        await module.showFreeSpace()?.value
        precondition(rig.presenter.posts.map(\.text) == [LowDiskPolicy.available(free: gb(50))], "free space shown")
        precondition(rig.presenter.posts[0].id == LowDiskModule.noticeID && !rig.presenter.posts[0].isFailure,
                     "a plain message")
        disk.fails = true
        await module.showFreeSpace()?.value
        precondition(rig.presenter.posts.last?.isFailure == true, "a failed read says so")
        precondition(rig.presenter.posts.last?.text == "Couldn’t read disk space", "in plain words")
        disk.fails = false
        precondition(rig.controller.run(entryID: "command:nc-check-disk-space"), "on: the launcher runs it")
        rig.controller.stop()
        precondition(module.showFreeSpace() == nil && module.check() == nil, "a stopped module reads nothing")
    }

    static func statusTap() async {
        let suite = "nc-LowDisk-module-test.\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        disk.free = gb(5)
        disk.fails = false

        let rig = Rig(suite: suite, on: true)
        defer { rig.controller.stop() }
        await rig.settle()
        guard let module = rig.module, let tap = rig.presenter.statusTap else { preconditionFailure("status with tap") }
        precondition(rig.controller.run(entryID: "command:nc-check-disk-space"), "the command runs while the status shows")
        await module.reporting?.value
        precondition(rig.presenter.posts.last?.text == LowDiskPolicy.available(free: gb(5)), "the command reads free space")
        precondition(rig.presenter.statuses == [lowDiskStatus], "the command leaves the status while still low")

        disk.free = gb(10)
        tap()
        await module.reporting?.value
        precondition(rig.presenter.posts.last?.text == LowDiskPolicy.available(free: gb(10)), "a tap reads free space again")
        precondition(rig.presenter.statuses == [lowDiskStatus], "a tap inside the margin keeps the status")

        disk.free = gb(11)
        tap()
        await module.reporting?.value
        precondition(rig.presenter.posts.last?.text == LowDiskPolicy.available(free: gb(11)), "a tap reports recovery")
        precondition(rig.presenter.statuses == [lowDiskStatus, nil], "a tap at the re-arm mark clears the status")
        precondition(rig.warnings.count == 1, "the command and taps never repeat the warning")
    }
}
