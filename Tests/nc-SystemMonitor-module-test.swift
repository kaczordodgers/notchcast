// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/SystemMonitorAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Service/SystemMonitorModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Service/MonitorSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
// notchcast-sources: Tests/nc-SystemMonitor-fixtures.swift
import SwiftUI

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-SystemMonitor-module-test: \(message)") }
}

/// Stands in for the live reads, so the descriptor compiles as shipped without touching the Mac.
extension MonitorSystem {
    static func live() -> MonitorSystem {
        MonitorSystem(read: { _, _ in preconditionFailure("the harness never reads the Mac") },
                      eject: { _ in preconditionFailure("the harness never ejects a real volume") },
                      sleep: { _ in preconditionFailure("the harness never sleeps") }, processorCount: 1)
    }
}

/// A scripted Mac on its own clock: each sleep moves the clock and runs the next step, which may end the loop.
@MainActor
final class FakeMac {
    var time: TimeInterval = 0
    var cpu = 0.2
    var pressure = MonitorPressure.normal
    var volumes: [MonitorVolume] = []
    var volumeReads = 0
    var ejects: [String] = []
    var whenEjectHeld: CheckedContinuation<Void, Never>?
    private var heldEject: CheckedContinuation<MonitorEjectResult, Never>?
    var reads: [Bool] = []
    var ranked: [Int] = []
    var sleeps: [Duration] = []
    var steps: [@MainActor () -> Void] = []
    /// The next read stays out until `release`; `whenHeld` resumes once it does.
    var hold = false
    var whenHeld: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<MonitorReading, Never>?
    private var busy: UInt64 = 0
    private var total: UInt64 = 0

    func read(_ detail: Bool, _ previous: [Int32: UInt64]) async -> MonitorReading {
        if hold {
            hold = false
            return await withCheckedContinuation { continuation in
                held = continuation
                whenHeld?.resume()
                whenHeld = nil
            }
        }
        reads.append(detail)
        if detail { volumeReads += 1 }
        ranked.append(previous.count)
        busy += UInt64(cpu * 1000)
        total += 1000
        let step = Double(reads.count)
        return MonitorFixtures.reading(at: time, busy: busy, total: total + 1000, received: UInt64(step) * 1000,
                                       sent: UInt64(step) * 100, detail: detail, pressure: pressure, step: step,
                                       volumes: detail ? volumes : [])
    }

    func sleep(_ duration: Duration) throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        time += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        if steps.isEmpty { throw CancellationError() }
        steps.removeFirst()()
    }

    /// Lands the held read with critical pressure, which would post a status if it were ever applied.
    func release() {
        held?.resume(returning: MonitorFixtures.reading(at: time, busy: 0, total: 1000, received: 0, sent: 0,
                                                        detail: true, pressure: .critical))
        held = nil
    }

    func eject(_ path: String) async -> MonitorEjectResult {
        ejects.append(path)
        return await withCheckedContinuation {
            heldEject = $0
            whenEjectHeld?.resume()
            whenEjectHeld = nil
        }
    }

    func waitForEject() async {
        guard heldEject == nil else { return }
        await withCheckedContinuation { whenEjectHeld = $0 }
    }

    func finishEject(_ result: MonitorEjectResult) {
        guard let heldEject else { preconditionFailure("no eject to finish") }
        self.heldEject = nil
        heldEject.resume(returning: result)
    }

    var system: MonitorSystem {
        MonitorSystem(read: { await self.read($0, $1) }, eject: { await self.eject($0) },
                      sleep: { try await self.sleep($0) }, processorCount: 4)
    }
}

@MainActor
final class Recorder: IslandPresenting {
    var pages: [IslandPage?] = []
    var statuses: [IslandStatus?] = []
    var notices: [IslandNotice] = []
    var action: (@MainActor (String) -> Void)?
    var tap: (@MainActor () -> Void)?
    var watcher: (@MainActor (Bool) -> Void)?
    var shown: [String] = []

    func showLevel(_ level: IslandLevel) { check(false, "the System add-on shows no level") }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { notices.append(notice) }
    func end(notice id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        check(id == MonitorPage.id, "one status, under the page's id")
        statuses.append(status)
        tap = onTap
    }

    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        check(id == MonitorPage.id, "the add-on posts only the System page")
        pages.append(page)
        action = onAction
    }

    func watchPages(id: String, onChange: (@MainActor (_ visible: Bool) -> Void)?) {
        check(id == MonitorPage.id, "the add-on watches only the System page")
        watcher = onChange
    }

    func showPage(id: String) { shown.append(id) }

    func row(named name: String) -> IslandPageRow? {
        pages.last.flatMap(\.self)?.blocks.compactMap {
            if case .row(let row) = $0 { row } else { nil }
        }.first { $0.title == name }
    }
}

/// The module as its hook starts it, on a scripted Mac: cadence, visibility, the hot glyph, Command-R, teardown.
@MainActor
@main
struct SystemMonitorModuleTests {
    static func main() async {
        switchShape()
        await hidden()
        await shown()
        await hot()
        await refresh()
        await switchOff()
        await staleRead()
        await eject()
        await ejectWhileClosed()
        await ejectAcrossSwitchOff()
        print("PASSED")
    }

    /// A step that shows or hides the page starts a new loop; wait for the last one.
    static func settle(_ module: SystemMonitorModule) async {
        while let loop = module.loop {
            await loop.value
            if module.loop == loop { return }
        }
    }

    static func make(_ mac: FakeMac, _ presenter: Recorder) -> (SystemMonitorModule, NotchcastContext) {
        let suite = "nc-system-monitor-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        let context = NotchcastContext(
            defaults: defaults,
            preferences: NotchcastPreferences(defaults: defaults, switches: SystemMonitorAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date(timeIntervalSince1970: 0) }, onTapsChanged: {})
        return (SystemMonitorModule(context: context, system: mac.system, locale: MonitorFixtures.locale), context)
    }

    static func switchShape() {
        check(SystemMonitorAddon.switches.map(\.id) == ["systemPage"], "the switch id is frozen")
        let entry = SystemMonitorAddon.switches[0]
        check(!entry.defaultEnabled && entry.requiredGrants.isEmpty && entry.dependencies.isEmpty,
              "off by default, and it needs no grant: no root, no Accessibility")
        let (_, context) = make(FakeMac(), Recorder())
        check(SystemMonitorAddon.makeModule(context) is SystemMonitorModule, "the switch has a module as its user path")
    }

    /// Closed, only the hot check reads: every 15 s, never the network or the process walk, and no page post.
    static func hidden() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.volumes = [MonitorFixtures.volume("Test Disk")]
        mac.steps = [{}, {}]
        module.start()
        module.start()
        await module.loop?.value
        check(mac.reads == [false, false, false], "three plain reads: \(mac.reads)")
        check(mac.sleeps == [MonitorBoard.hiddenInterval, MonitorBoard.hiddenInterval, MonitorBoard.hiddenInterval],
              "15 s apart while hidden")
        check(presenter.pages.count == 1 && presenter.pages[0]?.line.text == "Measuring…",
              "one page at start, so Home lists it; hidden reads post nothing more")
        check(presenter.statuses.isEmpty, "nothing hot, no status")
        check(mac.volumeReads == 0 && presenter.row(named: "Test Disk") == nil, "hidden reads never ask for volumes")
        module.stop()
    }

    /// On show it reads at once with the page's detail, again in half a second for the rates, then every 2 s.
    static func shown() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        var quick: IslandPage?
        mac.steps = [{
            presenter.watcher?(true)
            mac.steps = [{}, { quick = presenter.pages.last.flatMap(\.self) }, { presenter.watcher?(false) }]
        }]
        module.start()
        await settle(module)
        check(mac.reads == [false, true, true, true, false], "\(mac.reads)")
        check(mac.ranked == [0, 0, 2, 2, 0], "each detail read ranks against the last one's processes: \(mac.ranked)")
        check(Array(mac.sleeps.suffix(4)) == [.milliseconds(500), .seconds(2), .seconds(2), .seconds(15)],
              "half a second after the baseline, 2 s while shown, 15 s once hidden: \(mac.sleeps)")
        guard case .cards(let early) = quick?.blocks.first, case .notice(_, let down, _) = early.cards[3].body else {
            return check(false, "the page half a second after showing has its network tile")
        }
        check(down == "↓ 2 kB/s" && quick?.blocks.count == 4,
              "half a second in, the rates and processes show: \(down)")
        guard let page = presenter.pages.last.flatMap(\.self), case .cards(let tiles) = page.blocks.first else {
            return check(false, "the page shows tiles")
        }
        check(tiles.cards.allSatisfy { !$0.dimmed }, "every tile filled once two detail reads came in")
        check(page.blocks.count == 4, "the header and two processes under the tiles: \(page.blocks.count)")
        check(page.line.text == "Memory 50%", "Home names the busier of CPU and memory: \(page.line.text)")
        let posts = presenter.pages.count
        presenter.watcher?(false)
        check(presenter.pages.count == posts, "hiding twice changes nothing")
        module.stop()
    }

    static func hot() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.cpu = 0.95
        mac.steps = [{}, {}, { mac.cpu = 0.5 }, {}]
        module.start()
        await module.loop?.value
        check(presenter.statuses.count == 2, "hot once, cool once: \(presenter.statuses)")
        check(presenter.statuses[0]?.symbol == "cpu" && presenter.statuses[0]?.text == "Hot",
              "held over the limit on hidden reads, the closed island shows CPU Hot")
        check(presenter.statuses[1] == nil, "under 75 % the glyph goes")
        presenter.tap?()
        check(presenter.shown == [MonitorPage.id], "its tap opens the System page")
        mac.pressure = .critical
        mac.steps = [{}]
        presenter.watcher?(true)
        await module.loop?.value
        check(presenter.statuses.last??.symbol == "memorychip", "critical pressure shows at once")
        module.stop()
        check(presenter.statuses.last! == nil, "switching off clears the glyph")
    }

    static func refresh() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        mac.steps = [{ presenter.watcher?(true) }]
        module.start()
        await settle(module)
        let reads = mac.reads.count
        mac.steps = []
        presenter.action?(IslandPage.refreshAction)
        await module.loop?.value
        check(mac.reads.count == reads + 1, "Command-R reads at once")
        module.stop()
    }

    static func switchOff() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        module.start()
        let watcher = presenter.watcher
        let loop = module.loop
        mac.steps = [{ module.stop() }]
        await loop?.value
        check(presenter.pages.last! == nil, "switching off removes the page")
        let reads = mac.reads.count
        watcher?(true)
        check(module.loop == nil && mac.reads.count == reads, "after stop nothing samples, shown or not")
        module.stop()
        check(presenter.pages.count == 2, "a second stop posts nothing")
    }

    /// A read still out when the page hides or the switch goes off is dropped when it lands, even switched on again.
    static func staleRead() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        module.start()
        await module.loop?.value
        mac.hold = true
        presenter.watcher?(true)
        await withCheckedContinuation { mac.whenHeld = $0 }
        let late = module.loop
        presenter.watcher?(false)
        await settle(module)
        mac.release()
        await late?.value
        check(presenter.statuses.isEmpty, "a read that lands after the page hid is dropped")
        for restart in [false, true] {
            module.start()
            await settle(module)
            mac.hold = true
            presenter.watcher?(true)
            await withCheckedContinuation { mac.whenHeld = $0 }
            let late = module.loop
            module.stop()
            if restart {
                module.start()
                await settle(module)
            }
            mac.release()
            await late?.value
            check(presenter.statuses.isEmpty, "a read that lands after switch-off is dropped (on again: \(restart))")
        }
        module.stop()
    }

    static func eject() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        let volume = MonitorFixtures.volume("Test Disk")
        mac.volumes = [volume]
        module.start()
        presenter.watcher?(true)
        await settle(module)

        let reads = mac.volumeReads
        presenter.action?(MonitorVolumes.action(for: "/Volumes/Unknown"))
        check(module.ejectTasks.isEmpty, "a path outside the current list does nothing")
        let action = presenter.row(named: volume.name)?.id
        check(action == MonitorVolumes.action(for: volume.path), "the fixture is an eject button")
        presenter.action?(action!)
        let task = module.ejectTasks[volume.path]
        await mac.waitForEject()
        check(presenter.row(named: volume.name)?.trailing == "Ejecting…", "the row reports work")
        presenter.action?(action!)
        check(mac.ejects == [volume.path] && module.ejectTasks[volume.path] == task, "a second click starts no task")
        mac.finishEject(MonitorEjectResult(errorDomain: NSCocoaErrorDomain, errorCode: 769, holder: "Preview",
                                           stillMounted: true))
        await task?.value
        check(presenter.notices.last?.text == "Test Disk Is in Use by Preview" && presenter.notices.last?.isFailure == true,
              "busy posts a failure naming the holder")
        check(presenter.row(named: volume.name)?.id == action && mac.volumeReads == reads, "busy restores the button")

        presenter.action?(action!)
        let retry = module.ejectTasks[volume.path]
        await mac.waitForEject()
        mac.volumes = []
        mac.finishEject(MonitorEjectResult())
        await retry?.value
        await settle(module)
        check(mac.ejects == [volume.path, volume.path] && mac.volumeReads == reads + 1, "success rereads at once")
        check(presenter.notices.last?.text == "Ejected Test Disk" && presenter.row(named: volume.name) == nil,
              "success posts a notice and the disk is gone")
        module.stop()
    }

    static func ejectWhileClosed() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        let volume = MonitorFixtures.volume("Test Disk")
        mac.volumes = [volume]
        module.start()
        presenter.watcher?(true)
        await settle(module)
        presenter.action?(MonitorVolumes.action(for: volume.path))
        let task = module.ejectTasks[volume.path]
        await mac.waitForEject()

        presenter.watcher?(false)
        await settle(module)
        let pages = presenter.pages.count
        let volumeReads = mac.volumeReads
        mac.finishEject(MonitorEjectResult())
        await task?.value
        await settle(module)
        check(presenter.notices.last?.text == "Ejected Test Disk", "a result reaches the closed island")
        check(presenter.pages.count == pages && mac.volumeReads == volumeReads, "closed: no detail reads or page posts")
        module.stop()
    }

    static func ejectAcrossSwitchOff() async {
        let mac = FakeMac()
        let presenter = Recorder()
        let (module, _) = make(mac, presenter)
        let volume = MonitorFixtures.volume("Test Disk")
        let action = MonitorVolumes.action(for: volume.path)
        mac.volumes = [volume]
        for restart in [false, true] {
            module.start()
            presenter.watcher?(true)
            await settle(module)
            presenter.action?(action)
            let task = module.ejectTasks[volume.path]
            await mac.waitForEject()
            module.stop()
            check(task?.isCancelled == true && module.ejectTasks.isEmpty, "stop cancels and drops owned ejects")
            if restart {
                module.start()
                presenter.watcher?(true)
                await settle(module)
                check(presenter.row(named: volume.name)?.id == action, "the new session starts with a clean row")
            }
            let pages = presenter.pages.count
            mac.finishEject(MonitorEjectResult())
            await task?.value
            check(presenter.notices.isEmpty && presenter.pages.count == pages, "no late result after switch-off")
        }
        module.stop()
    }
}
