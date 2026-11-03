// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/MusicSelection.swift
// notchcast-sources: Tinycast/Features/Music/Model/LastPlayer.swift
// notchcast-sources: Tinycast/Features/Music/Service/MusicModel.swift
// notchcast-sources: Tinycast/Features/Music/Service/PlayerApps.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation

@MainActor
private final class FakeSource: NowPlayingSource {
    enum Failure: Error { case unreadable }
    var track: NowPlaying?
    var fails = false
    var reads = 0
    var commands: [PlayerCommand] = []
    var onChange: (@MainActor () -> Void)?
    var unwatchCount = 0
    var held: CheckedContinuation<NowPlaying?, any Error>?
    var holdRead = false

    func watch(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func unwatch() { onChange = nil; unwatchCount += 1 }
    func read() async throws -> NowPlaying? {
        reads += 1
        if holdRead { return try await withCheckedThrowingContinuation { held = $0 } }
        if fails { throw Failure.unreadable }
        return track
    }
    func send(_ command: PlayerCommand) { commands.append(command) }
}

@MainActor
private final class FakeClock {
    private struct Waiter {
        var deadline: Duration
        var continuation: CheckedContinuation<Void, any Error>
    }

    var time = Duration.zero
    var waits: [Duration] = []
    var immediate = true
    private var waiters: [UUID: Waiter] = [:]

    func sleep(_ duration: Duration) async throws {
        if immediate { return }
        let id = UUID()
        waits.append(duration)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                waiters[id] = Waiter(deadline: time + duration, continuation: $0)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func advance(_ duration: Duration) {
        time += duration
        for (id, waiter) in waiters where waiter.deadline <= time {
            waiters.removeValue(forKey: id)?.continuation.resume()
        }
    }
}

@MainActor
private final class Desk {
    let defaults: UserDefaults
    let suite = "music-model-test.\(UUID().uuidString)"
    let system = FakeSource()
    let soloist = FakeSource()
    let clock = FakeClock()
    var installed: Set<String> = [LastPlayer.spotify, "test.player"]
    var opened: [String] = []
    var played: [String] = []
    var opening: CheckedContinuation<Void, any Error>?
    var holdOpen = false
    var failOpen = false
    var playFailures = 0
    var date = Date(timeIntervalSince1970: 100)
    lazy var model = MusicModel(defaults: defaults, apps: apps, now: { [unowned self] in date },
                                sleep: { [clock] in try await clock.sleep($0) })

    init() { defaults = UserDefaults(suiteName: suite)! }

    isolated deinit { defaults.removePersistentDomain(forName: suite) }

    var apps: PlayerApps {
        PlayerApps(isInstalled: { [unowned self] in installed.contains($0) }, isRunning: { _ in false },
                   open: { [unowned self] id in
                       opened.append(id)
                       if failOpen { throw FakeSource.Failure.unreadable }
                       if holdOpen { try await withCheckedThrowingContinuation { opening = $0 } }
                   }, play: { [unowned self] in
                       played.append($0)
                       if playFailures > 0 {
                           playFailures -= 1
                           throw NSError(domain: NSOSStatusErrorDomain, code: playFailures == 1 ? -609 : -600)
                       }
                   }, watchLaunches: { _ in [] }, quit: { _ in false },
                   canPlay: { $0 == "test.player" || $0 == LastPlayer.spotify })
    }

    func start() async {
        model.setSystemSource(system)
        model.setSoloistSource(soloist)
        model.setEnabled(true)
        await settle()
    }

    func stop() { model.setEnabled(false) }
}

@MainActor
private func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

private func track(_ origin: NowPlaying.Origin = .system, playing: Bool = true,
                   bundleID: String? = "test.player", title: String = "Track") -> NowPlaying {
    NowPlaying(title: title, artist: "Artist", album: "Album", app: "Player", bundleID: bundleID,
               duration: 120, elapsed: 10, stamp: Date(timeIntervalSince1970: 100),
               isPlaying: playing, artwork: nil, origin: origin)
}

@main
struct MusicModelTest {
    @MainActor
    static func main() async {
        selection()
        await lifecycleAndCommands()
        await retries()
        await staleReads()
        await lastPlayer()
        await resume()
        await coldLaunch()
        await disabledFailures()
        await failureRecovery()
        capabilityCache()
        print("PASS music-model: selection, routing, 1/2/4s retries, stale reads, last player and cancellation")
    }

    @MainActor
    static func capabilityCache() {
        let suite = "last-player-cache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        let player = LastPlayer(defaults: defaults, canPlay: { id in calls += 1; return id == "test.player" })
        player.setEnabled(true)
        for _ in 0..<5 {
            player.hear(track())
            player.hear(track(bundleID: "unsupported"))
        }
        assert(calls == 2)
    }

    @MainActor
    static func failureRecovery() async {
        let desk = Desk()
        await desk.start()
        desk.failOpen = true
        await desk.model.openReplacement(startingPlayback: false).value
        assert(desk.model.failure != nil)
        desk.model.send(.pause)
        assert(desk.model.failure == nil)
        await desk.model.openReplacement(startingPlayback: false).value
        assert(desk.model.failure != nil)
        desk.system.track = track()
        desk.system.onChange?()
        await settle()
        assert(desk.model.failure == nil)
        desk.stop()
    }

    static func selection() {
        let other = track()
        let paused = track(playing: false)
        let solo = track(.soloist)
        let soloPaused = track(.soloist, playing: false)
        assert(MusicSelection.pick(system: other, soloist: solo) == other)
        assert(MusicSelection.pick(system: other, soloist: soloPaused) == other)
        assert(MusicSelection.pick(system: paused, soloist: solo) == solo)
        assert(MusicSelection.pick(system: paused, soloist: soloPaused) == soloPaused)
        assert(MusicSelection.pick(system: paused, soloist: nil) == paused)
        assert(MusicSelection.pick(system: nil, soloist: soloPaused) == soloPaused)
        assert(MusicSelection.pick(system: nil, soloist: nil) == nil)
        var mirror = other
        mirror.app = "Soloist"
        mirror.bundleID = nil
        assert(MusicSelection.pick(system: mirror, soloist: solo) == solo)
        assert(MusicSelection.pick(system: mirror, soloist: nil) == nil)
    }

    @MainActor
    static func lifecycleAndCommands() async {
        let desk = Desk()
        desk.system.track = track()
        desk.soloist.track = track(.soloist, bundleID: "test.soloist")
        desk.model.lastPlayer.setEnabled(true)
        desk.model.setSystemSource(desk.system)
        assert(desk.system.reads == 0 && desk.system.onChange == nil)
        desk.model.send(.play)
        assert(desk.system.commands.isEmpty)
        await desk.start()
        assert(desk.model.nowPlaying?.origin == .system)
        assert(desk.model.lastPlayer.bundleID == "test.player")
        desk.model.send(.next)
        assert(desk.system.commands == [.next] && desk.soloist.commands.isEmpty)
        desk.date.addTimeInterval(5)
        assert(desk.model.position == 15)
        desk.system.track?.isPlaying = false
        desk.system.onChange?()
        await settle()
        assert(desk.model.nowPlaying?.origin == .soloist)
        desk.model.send(.seek(35))
        desk.model.send(.volume(0.4))
        assert(desk.soloist.commands == [.seek(35), .volume(0.4)])
        desk.model.setSoloistSource(nil)
        assert(desk.model.nowPlaying?.origin == .system)
        assert(desk.model.position == 10)
        desk.clock.advance(.seconds(3600))
        await settle()
        assert(desk.system.reads == 2 && desk.soloist.reads == 1)
        desk.stop()
        assert(desk.model.nowPlaying == nil && desk.model.failure == nil)
        let suspended = FakeSource()
        suspended.holdRead = true
        var released: MusicModel? = MusicModel(defaults: desk.defaults, apps: desk.apps)
        weak var weakModel = released
        released?.setSystemSource(suspended)
        released?.setEnabled(true)
        await settle()
        released = nil
        assert(weakModel == nil && suspended.onChange == nil)
        suspended.held?.resume(returning: track())
        suspended.held = nil
        await settle()
        assert(desk.system.onChange == nil && desk.soloist.onChange == nil)
    }

    @MainActor
    static func retries() async {
        let desk = Desk()
        desk.clock.immediate = false
        desk.system.fails = true
        desk.soloist.track = track(.soloist)
        await desk.start()
        assert(desk.model.failure == .unreadable(.system))
        assert(desk.model.nowPlaying?.origin == .soloist)
        assert(desk.clock.waits == [.seconds(1)])
        for _ in 0..<10 { desk.system.onChange?() }
        await settle()
        assert(desk.system.reads == 1)
        desk.clock.advance(.milliseconds(999))
        await settle()
        assert(desk.system.reads == 1)
        desk.clock.advance(.milliseconds(1))
        await settle()
        assert(desk.system.reads == 2)
        desk.clock.advance(.seconds(2))
        await settle()
        assert(desk.system.reads == 3)
        desk.clock.advance(.seconds(4))
        await settle()
        assert(desk.system.reads == 4)
        assert(desk.clock.waits == [.seconds(1), .seconds(2), .seconds(4)])
        desk.clock.advance(.seconds(3600))
        await settle()
        assert(desk.system.reads == 4)
        desk.system.onChange?()
        await settle()
        assert(desk.system.reads == 5 && desk.clock.waits.count == 4)
        assert(desk.clock.waits.last == .seconds(1))
        desk.clock.advance(.seconds(1))
        await settle()
        assert(desk.clock.waits.last == .seconds(2))
        desk.clock.advance(.seconds(2))
        await settle()
        desk.clock.advance(.seconds(4))
        await settle()
        desk.system.fails = false
        desk.system.track = track()
        desk.system.onChange?()
        await settle()
        assert(desk.model.failure == nil && desk.model.nowPlaying?.origin == .system)
        desk.system.fails = true
        desk.system.onChange?()
        await settle()
        assert(desk.clock.waits.last == .seconds(1))
        desk.stop()
        let reads = desk.system.reads
        desk.clock.advance(.seconds(10))
        await settle()
        assert(desk.system.reads == reads)
    }

    @MainActor
    static func staleReads() async {
        let desk = Desk()
        desk.system.holdRead = true
        await desk.start()
        assert(desk.system.held != nil)
        let oldWatch = desk.system.onChange
        let fresh = FakeSource()
        fresh.track = track(title: "New")
        desk.model.setSystemSource(fresh)
        await settle()
        desk.system.held?.resume(returning: track(title: "Old"))
        desk.system.held = nil
        await settle()
        assert(desk.model.nowPlaying?.title == "New")
        oldWatch?()
        await settle()
        assert(fresh.reads == 1)
        fresh.holdRead = true
        fresh.onChange?()
        await settle()
        desk.stop()
        fresh.held?.resume(returning: track(title: "Late"))
        fresh.held = nil
        await settle()
        assert(desk.model.nowPlaying == nil && desk.model.failure == nil)
    }

    @MainActor
    static func lastPlayer() async {
        let desk = Desk()
        desk.defaults.set(LastPlayer.appleMusic, forKey: LastPlayer.key)
        assert(desk.model.lastPlayer.bundleID == nil)
        desk.model.lastPlayer.setEnabled(true)
        desk.system.track = track(bundleID: LastPlayer.appleMusic)
        await desk.start()
        assert(desk.model.lastPlayer.bundleID == nil)
        desk.system.track = track(playing: false)
        desk.system.onChange?()
        await settle()
        assert(desk.model.lastPlayer.bundleID == nil)
        desk.system.track = track()
        desk.system.onChange?()
        await settle()
        assert(desk.model.lastPlayer.bundleID == "test.player")
        let again = LastPlayer(defaults: desk.defaults, canPlay: desk.apps.canPlay)
        assert(again.bundleID == "test.player")
        desk.model.lastPlayer.hear(track(bundleID: "com.apple.Safari"))
        assert(desk.model.lastPlayer.bundleID == "test.player")
        desk.defaults.set("com.apple.Safari", forKey: LastPlayer.key)
        assert(LastPlayer(defaults: desk.defaults, canPlay: desk.apps.canPlay).bundleID == nil)
        desk.defaults.set("test.player", forKey: LastPlayer.key)
        desk.system.track = track(bundleID: LastPlayer.appleMusic)
        desk.system.onChange?()
        await settle()
        assert(desk.model.lastPlayer.bundleID == "test.player")
        assert(desk.defaults.string(forKey: LastPlayer.key) == "test.player")
        desk.model.lastPlayer.setEnabled(false)
        desk.model.lastPlayer.hear(track(bundleID: LastPlayer.spotify))
        assert(desk.model.lastPlayer.bundleID == "test.player")
        desk.stop()
    }

    @MainActor
    static func resume() async {
        let desk = Desk()
        await desk.start()
        desk.model.send(.play)
        assert(desk.system.commands == [.play])
        desk.model.lastPlayer.setEnabled(true)
        desk.model.send(.togglePlayPause)
        await settle()
        assert(desk.opened == [LastPlayer.spotify] && desk.played == [LastPlayer.spotify])
        desk.model.lastPlayer.hear(track())
        desk.model.send(.play)
        await settle()
        assert(desk.opened.last == "test.player" && desk.played.last == "test.player")
        desk.installed.remove("test.player")
        desk.model.send(.play)
        await settle()
        assert(desk.opened.last == LastPlayer.spotify)
        desk.holdOpen = true
        desk.model.send(.play)
        await settle()
        let beforeDisable = desk.played.count
        desk.model.lastPlayer.setEnabled(false)
        desk.model.lastPlayer.setEnabled(true)
        desk.opening?.resume()
        desk.opening = nil
        await settle()
        assert(desk.played.count == beforeDisable)
        desk.holdOpen = false
        desk.installed = []
        desk.model.send(.play)
        await settle()
        assert(desk.model.failure == .noReplacement)
        desk.installed = [LastPlayer.spotify]
        desk.failOpen = true
        desk.model.send(.play)
        await settle()
        assert(desk.model.failure == .launchFailed(LastPlayer.spotify))
        desk.failOpen = false
        desk.holdOpen = true
        desk.model.send(.play)
        await settle()
        let played = desk.played.count
        desk.stop()
        desk.opening?.resume()
        desk.opening = nil
        await settle()
        assert(desk.played.count == played && desk.model.failure == nil)
        var released: MusicModel? = MusicModel(defaults: desk.defaults, apps: desk.apps)
        weak var weakModel = released
        released?.lastPlayer.setEnabled(true)
        released?.setEnabled(true)
        released?.send(.play)
        await settle()
        assert(desk.opening != nil)
        released = nil
        assert(weakModel == nil)
        desk.opening?.resume()
        desk.opening = nil
        await settle()
        assert(desk.played.count == played)
    }

    @MainActor
    static func coldLaunch() async {
        let desk = Desk()
        desk.clock.immediate = false
        desk.playFailures = 2
        let task = desk.model.openReplacement(startingPlayback: true)
        await settle()
        assert(desk.played.isEmpty && desk.clock.waits == [.seconds(1)])
        for count in 1...3 {
            desk.clock.advance(.seconds(1))
            await settle()
            assert(desk.played.count == count)
        }
        await task.value
        assert(desk.model.failure == nil)
        desk.playFailures = 3
        let failed = desk.model.openReplacement(startingPlayback: true)
        await settle()
        for _ in 0..<3 {
            desk.clock.advance(.seconds(1))
            await settle()
        }
        await failed.value
        assert(desk.played.count == 6 && desk.model.failure == .playbackFailed(LastPlayer.spotify))
        let cancelled = desk.model.openReplacement(startingPlayback: true)
        await settle()
        cancelled.cancel()
        await settle()
        desk.clock.advance(.seconds(1))
        await cancelled.value
        assert(desk.played.count == 6)
    }

    @MainActor
    static func disabledFailures() async {
        let desk = Desk()
        assert(!desk.model.isEnabled)
        desk.installed = []
        await desk.model.openReplacement(startingPlayback: true).value
        assert(desk.model.failure == .noReplacement)
        desk.installed = [LastPlayer.spotify]
        desk.failOpen = true
        await desk.model.openReplacement(startingPlayback: true).value
        assert(desk.model.failure == .launchFailed(LastPlayer.spotify))
        desk.failOpen = false
        await desk.model.openReplacement(startingPlayback: false).value
        assert(desk.model.failure == nil)
    }
}
