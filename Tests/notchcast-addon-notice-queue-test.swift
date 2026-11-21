// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandMeetingExpansion.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPlayerSource.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenter.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandKeyHold.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import AppKit
import Foundation
import Observation

/// Only what IslandPresenter reaches on AppCore, so the shipped presenter runs without the app.
@MainActor @Observable
final class AppCore {
    static let shared = AppCore()
    let island = StubIsland()
    let palette = StubPalette()
    var isShowingDialog = false
}

@MainActor @Observable final class StubPalette { var isVisible = false }

@MainActor
final class StubIsland {
    var resting: IslandController? = IslandController()
    var displays: [UInt32: IslandController] = [:]
    func controller(on display: UInt32) -> IslandController? { displays[display] }
    let overlays = StubOverlays()
    let pillMenu = StubPillMenu()
    func frosted(on screen: NSScreen?) -> Bool { false }
}

@MainActor final class StubOverlays { func placeReport(_ panel: NSPanel, screen: NSScreen?) {} }
@MainActor final class StubPillMenu { func refit(keepingSelection: Bool = false) {} }

/// The resting pill: `shown` is every notice it was handed, in order.
@MainActor
final class IslandController {
    var shown: [String] = []
    var notice: IslandNotice? { didSet { if let notice, notice != oldValue { shown.append(notice.text) } } }
    var statuses: [IslandStatus] = []
    var level: IslandLevel?
    var expanded = false
    var glance: String?
    var song: IslandNowPlaying?
    var songChange = false
    var notchWidth: CGFloat?
    var screenShape: CGRect?
}

/// The page host as shipped decides: a page, or a bare island, opens it instead of the pill.
@MainActor
final class IslandPageHost {
    private(set) var deck = IslandPageDeck()
    private(set) var isOpen = false
    private(set) var watched: [String: Bool] = [:]
    private(set) var noticeTap: (@MainActor () -> Void)?
    private(set) var shown: [String] = []
    func showPage(id: String) { shown.append(id) }
    func set(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) { deck.set(page, id: id) }
    func watch(id: String, onChange: (@MainActor (Bool) -> Void)?) { watched[id] = onChange != nil }
    func show(_ notice: IslandNotice?, onTap: (@MainActor () -> Void)?) {
        deck.show(notice, tappable: onTap != nil)
        noticeTap = onTap
    }
    @discardableResult
    func hover(_ hovered: Bool, on resting: IslandController?, glance: Bool = false) -> Bool {
        isOpen = hovered && deck.opens(glance: glance) && resting != nil
        return isOpen
    }
}

final class HUDPanel: NSPanel {
    func fadeIn(duration: TimeInterval, order: () -> Void) {}
    func fadeOut(duration: TimeInterval) {}
    func cancelFade() {}
}

final class IslandLevelBand: NSView { var art: IslandLevelArt?; func restyle(frosted: Bool) {} }

struct IslandLevelArt {
    init(_ level: IslandLevel, notch: Bool, frosted: Bool) {}
    var bandSize: CGSize { .zero }
}

enum Theme { enum Duration { static let enter: TimeInterval = 0; static let exit: TimeInterval = 0 } }

enum MusicNoticeAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "musicNotice", title: "Music", subtitle: "", category: .notices)]
    static let commands = [
        NotchcastCommand(slug: "music-notice", name: "Music", symbol: "circle", switchID: "musicNotice") { context in
            context.presenter.post(
                IslandNotice(id: "musicBlock", text: "Couldn't Stop Apple Music Opening", isFailure: true), onTap: nil)
        },
    ]
}

enum AwakeNoticeAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "awakeNotice", title: "Awake", subtitle: "", category: .notices)]
    static let commands = [
        NotchcastCommand(slug: "awake-notice", name: "Awake", symbol: "circle", switchID: "awakeNotice") { context in
            context.presenter.post(IslandNotice(id: "awakeNotice", text: "Keeping Your Mac Awake"), onTap: nil)
        },
    ]
}

/// Time moves only when the test says so; a sleeper wakes on the main actor at its own deadline.
@MainActor
final class ManualClock {
    /// Whole milliseconds, so a deadline lands on the dwell rather than a rounding error off it.
    private var tick = 0
    private var sleepers: [(deadline: Int, wake: CheckedContinuation<Void, Never>)] = []

    var now: TimeInterval { TimeInterval(tick) / 1000 }

    func sleep(_ seconds: TimeInterval) async {
        let deadline = tick + max(Int((seconds * 1000).rounded()), 1)
        await withCheckedContinuation { sleepers.append((deadline, $0)) }
    }

    /// Lets tasks already started go to sleep first, then wakes each due one in deadline order.
    func advance(by seconds: TimeInterval) async {
        await settle()
        let target = tick + Int((seconds * 1000).rounded())
        while let next = sleepers.indices.min(by: { sleepers[$0].deadline < sleepers[$1].deadline }),
              sleepers[next].deadline <= target {
            let sleeper = sleepers.remove(at: next)
            tick = max(tick, sleeper.deadline)
            sleeper.wake.resume()
            await settle()
        }
        tick = target
        await settle()
    }

    /// Every presenter task runs on the main actor, so yielding drains them in order.
    func settle() async { for _ in 0..<10 { await Task.yield() } }
}

@main @MainActor
struct AddonNoticeQueueTest {
    static var failures = 0
    static let clock = ManualClock()

    static func check(_ label: String, _ ok: Bool) {
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static let dwell: TimeInterval = 2.4 // the stock message HUD dwell add-ons were promised
    static let step: TimeInterval = 0.01

    /// An `uncover` that adds a pill hands it over as IslandCoordinator.rebuild does.
    static func checkHeld(_ label: String, _ text: String, run: () -> Bool, cover: () -> Void,
                          uncover: () -> IslandController?) async {
        cover()
        await clock.settle()
        check("\(label): the add-on notice runs", run())
        await clock.advance(by: dwell + 1)
        let pill = uncover()
        await clock.settle()
        print("\(label): showing once uncovered: \(pill?.notice?.text ?? "nothing")")
        check("\(label): the notice did not expire unseen", pill?.notice?.text == text)
        let dwell = pill?.notice?.dwell ?? Self.dwell
        await clock.advance(by: dwell - step)
        check("\(label): it still shows just before a full dwell", pill?.notice?.text == text)
        await clock.advance(by: step)
        check("\(label): it goes exactly at a full dwell once seen", pill?.notice == nil)
    }

    /// D7, D16: a new song grows a notched pill for one dwell; a meeting, notice or no notch never.
    static func songChange(_ presenter: IslandPresenter) async {
        let pill = AppCore.shared.island.resting!
        pill.notchWidth = 180
        func song(_ id: String, playing: Bool = true) -> IslandNowPlaying {
            IslandNowPlaying(title: "Song " + id, artist: "Juno Vale", artwork: nil,
                             time: IslandMediaTime(elapsed: 1, duration: 200, rate: 1, sampledAt: Date()),
                             isPlaying: playing, id: id)
        }
        presenter.setSong(song("a"))
        check("the song reaches the pill without its running time", pill.song?.id == "a" && pill.song?.time == nil)
        check("the first song seen never grows the pill", !pill.songChange)
        presenter.setSong(song("a", playing: false))
        check("a pause is no song change", !pill.songChange && pill.song?.isPlaying == false)
        presenter.setSong(song("b"))
        check("a new song grows a notched pill", pill.songChange)
        await clock.advance(by: dwell - step)
        check("for one message dwell", pill.songChange)
        await clock.advance(by: step)
        check("then settles back to the glance", !pill.songChange)
        presenter.setSong(song("c"))
        presenter.post(IslandNotice(id: "cut", text: "Copied"), onTap: nil)
        check("a notice cuts the song change", !pill.songChange)
        presenter.end(notice: "cut")
        check("and it does not come back", !pill.songChange)
        pill.glance = "Standup"
        presenter.setSong(song("d"))
        check("a meeting glance outranks the song change", !pill.songChange)
        pill.glance = nil
        pill.notchWidth = nil
        presenter.setSong(song("e"))
        check("without a notch the pill already names the song", !pill.songChange && pill.song?.id == "e")
        final class SilentSource: IslandPlayerSource { func perform(_ action: IslandPlayerAction) {} }
        presenter.showPlayer(song("f"), source: SilentSource())
        check("showPlayer hands the song to the pill", pill.song?.id == "f")
        let arrived = IslandController()
        presenter.restore(arrived, resting: true)
        check("a rebuilt pill gets the song without a change", arrived.song?.id == "f" && !arrived.songChange)
        presenter.showPlayer(nil, source: SilentSource())
        check("nil clears the song", pill.song == nil && !pill.songChange)
    }

    static func checkPlacement(_ presenter: IslandPresenter, resting: IslandController) async {
        let island = AppCore.shared.island
        let first = IslandController()
        let second = IslandController()
        island.displays = [2: first, 3: second]
        let notice = IslandNotice(id: "placed", text: "Placed", seconds: dwell)
        presenter.place(notice: notice.id, on: 2)
        presenter.post(notice, onTap: nil)
        check("only the chosen display gets the notice", resting.notice == nil && first.notice == notice)
        presenter.hoverChanged(true)
        presenter.place(notice: notice.id, on: 3)
        check("the hop clears the first display", first.notice == nil && second.notice == notice)
        await clock.advance(by: dwell)
        check("the away notice dwells even while the resting pill is hovered", second.notice == nil)
        presenter.hoverChanged(false)
        presenter.post(notice, onTap: nil)
        check("expiry clears placement for the next post", resting.notice == notice)
        presenter.place(notice: notice.id, on: 2)
        island.displays[2] = nil
        presenter.restingChanged()
        check("a disconnected display falls back to the resting pill", first.notice == nil && resting.notice == notice)
        island.displays[2] = first
        presenter.end(notice: notice.id)
        presenter.post(notice, onTap: nil)
        check("end clears placement for the next post", resting.notice == notice && first.notice == nil)
        presenter.end(notice: notice.id)
        island.displays = [:]
    }

    static func main() async {
        _ = NSApplication.shared
        let suite = "nc-notice-queue-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let system = FakeSystem()
        let presenter = IslandPresenter(now: { clock.now }, sleep: { await clock.sleep($0) })
        let controller = NotchcastController(addons: [MusicNoticeAddon.self, AwakeNoticeAddon.self],
                                             defaults: defaults, hub: system.makeHub(),
                                             dictation: FakeDictation(), presenter: presenter)
        controller.start()
        controller.preferences.set("musicNotice", on: true)
        controller.preferences.set("awakeNotice", on: true)
        await clock.settle()
        let pill = AppCore.shared.island.resting!
        let first = "Couldn't Stop Apple Music Opening"
        let second = "Keeping Your Mac Awake"

        check("the first add-on notice runs", controller.run(entryID: "command:nc-music-notice"))
        check("the second add-on notice runs", controller.run(entryID: "command:nc-awake-notice"))
        print("shown right after both posts: \(pill.shown); showing: \(pill.notice?.text ?? "nothing")")
        check("the newer notice shows on top", pill.notice?.text == second)
        await clock.advance(by: dwell - step)
        check("the newer notice still shows just before its dwell ends", pill.notice?.text == second)
        await clock.advance(by: step)
        print("shown once the newer notice dwelled out: \(pill.shown)")
        check("the first notice returns exactly when the second dwells out", pill.shown == [first, second, first])
        await clock.advance(by: 10)
        check("the queue empties", pill.notice == nil)
        await checkPlacement(presenter, resting: pill)
        let core = AppCore.shared
        let music = { controller.run(entryID: "command:nc-music-notice") }
        await checkHeld("launcher", first, run: music, cover: { core.palette.isVisible = true }) {
            core.palette.isVisible = false
            return core.island.resting
        }
        await checkHeld("question", second, run: { controller.run(entryID: "command:nc-awake-notice") },
                        cover: { core.isShowingDialog = true }) {
            core.isShowingDialog = false
            return core.island.resting
        }
        await checkHeld("no display", first, run: music, cover: { core.island.resting = nil }) {
            let arrived = IslandController()
            core.island.resting = arrived
            presenter.restore(arrived, resting: true)
            presenter.restingChanged()
            return arrived
        }
        await clock.advance(by: 10)
        let hovered = core.island.resting!
        presenter.setStatus(IslandStatus(id: "awake", symbol: "moon", label: "Keeping Awake"), for: "awake", onTap: nil)
        presenter.setPage(IslandPage(id: "player", title: "Player", symbol: "music.note", order: 10,
                                     line: IslandPageLine(text: "A song"), blocks: []), id: "player", onAction: nil)
        presenter.hoverChanged(true)
        check("a page takes the hover, so the pill keeps its short form", hovered.notice == nil && !hovered.expanded)
        presenter.setPage(nil, id: "player", onAction: nil)
        check("with no page, hover opens the pill's long form",
              hovered.notice?.text == "Keeping Awake" && hovered.expanded)
        presenter.hoverChanged(false)
        check("and leaving closes it", hovered.notice == nil && !hovered.expanded)
        let ready = IslandStatus(id: "update", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")
        presenter.setStatus(ready, for: ready.id, onTap: nil)
        presenter.hoverChanged(true)
        check("a hovered status shows its name", core.island.resting?.notice?.id == "hover.update")
        core.island.resting?.glance = "Standup"
        presenter.meetingChanged(.init(id: "standup", start: Date(timeIntervalSince1970: 0)))
        check("a meeting glance arriving on a hovered island replaces the status name (#1001)",
              core.island.resting?.notice == nil && core.island.resting?.expanded == true)
        presenter.hoverChanged(false)
        core.island.resting?.glance = nil
        presenter.meetingChanged(nil)
        var rang = 0
        presenter.post(IslandNotice(id: "ring", symbol: "timer", text: "Timer done", seconds: 60), onTap: { rang += 1 })
        check("with no page a click on the island runs the notice's own tap", presenter.tap != nil)
        presenter.setPage(IslandPage(id: "player", title: "Player", symbol: "music.note", order: 10,
                                     line: IslandPageLine(text: "A song"), blocks: []), id: "player", onAction: nil)
        check("with a page a click opens it instead, so no page is out of reach (#1005)", presenter.tap == nil)
        check("and the notice heads the open page as a button row",
              presenter.pages.deck.notice == IslandPageRow(id: IslandPageDeck.noticeID, symbol: "timer",
                                                           title: "Timer done"))
        presenter.pages.noticeTap?()
        check("whose click runs the notice's own tap", rang == 1)
        presenter.end(notice: "ring")
        check("once it ends the shown status takes the row, plain with no tap",
              presenter.pages.deck.notice?.title == "Update ready" && presenter.pages.deck.notice?.id == nil)
        presenter.setPage(nil, id: "player", onAction: nil)
        presenter.watchPages(id: "player") { _ in }
        check("an owner's watcher reaches the page host", presenter.pages.watched == ["player": true])
        presenter.showPage(id: "player")
        check("a command's showPage reaches the page host", presenter.pages.shown == ["player"])
        presenter.setStatus(nil, for: "awake", onTap: nil)
        presenter.setStatus(nil, for: ready.id, onTap: nil)
        presenter.hoverChanged(true)
        check("a bare island's hover opens the pages' Home, not the pill (#884)", presenter.pages.isOpen)
        core.island.resting?.glance = "Standup"
        presenter.hoverChanged(true)
        check("with no page a meeting glance keeps its own expansion", !presenter.pages.isOpen)
        presenter.hoverChanged(false)
        core.island.resting?.glance = nil
        await songChange(presenter)
        controller.stop()
        print(failures == 0 ? "PASS AddonNoticeQueueTest" : "FAILED \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
