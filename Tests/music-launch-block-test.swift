// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/LastPlayer.swift
// notchcast-sources: Tinycast/Features/Music/Model/MusicLaunchPolicy.swift
// notchcast-sources: Tinycast/Features/Music/Service/MusicLaunchBlocker.swift
// notchcast-sources: Tinycast/Features/Music/Service/PlayerApps.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift Tinycast/Platform/ProcessExit.swift
import AppKit

@MainActor
private final class FakeApps {
    var running: Set<String> = []
    var quits: [PlayerApps.Launch] = []
    var handlers: [@MainActor (PlayerApps.Launch) -> Void] = []
    var canQuit = true
    var replacements: [Bool] = []
    var time: TimeInterval = 100
    var gestureAge: TimeInterval = .infinity

    var apps: PlayerApps {
        PlayerApps(isInstalled: { _ in false }, isRunning: { [unowned self] in running.contains($0) },
                   open: { _ in }, play: { _ in }, watchLaunches: { [unowned self] handler in
                       handlers.append(handler)
                       return []
                   }, quit: { [unowned self] launch in
                       quits.append(launch)
                       return canQuit
                   })
    }

    func launch(_ processID: pid_t, id: String = "com.apple.Music") {
        for handler in handlers { handler(.init(bundleID: id, processID: processID)) }
    }

    func blocker() -> MusicLaunchBlocker {
        MusicLaunchBlocker(apps: apps, uptime: { [unowned self] in time },
                           gestureAge: { [unowned self] in gestureAge },
                           openReplacement: { [weak self] shouldPlay in
                               Task { [weak self] in
                                   self?.replacements.append(shouldPlay)
                               }
                           })
    }
}

@main
struct MusicLaunchBlockTest {
    @MainActor
    static func main() async throws {
        policy()
        await launches()
        await lifecycle()
        await cancellation()
        print("PASS music-launch-block: two-second window, gesture precedence, one key/launch, no-key preservation")
        if ProcessInfo.processInfo.environment["TINYCAST_TEST_MUSIC_BLOCK_LIVE"] == "1" {
            try await live()
        }
    }

    static func policy() {
        assert(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: nil, gestureAge: .infinity))
        assert(MusicLaunchPolicy.shouldBlock(now: 100, keyAt: 100, gestureAge: .infinity))
        assert(MusicLaunchPolicy.shouldBlock(now: 102, keyAt: 100, gestureAge: 3))
        assert(!MusicLaunchPolicy.shouldBlock(now: 102.001, keyAt: 100, gestureAge: .infinity))
        assert(!MusicLaunchPolicy.shouldBlock(now: 99, keyAt: 100, gestureAge: .infinity))
        assert(!MusicLaunchPolicy.shouldBlock(now: 101, keyAt: 100, gestureAge: 0.5))
        assert(!MusicLaunchPolicy.shouldBlock(now: 101, keyAt: 100, gestureAge: 1))
        assert(!MusicLaunchPolicy.shouldBlock(now: .nan, keyAt: 100, gestureAge: .infinity))
        assert(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: .infinity, gestureAge: .infinity))
        assert(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: 100, gestureAge: .nan))
        assert(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: -1, gestureAge: .infinity))
    }

    @MainActor
    static func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    @MainActor
    static func launches() async {
        let fake = FakeApps()
        let blocker = fake.blocker()
        assert(fake.handlers.isEmpty)
        blocker.noteMediaKey(.playPause)
        blocker.setEnabled(true)
        fake.launch(1)
        assert(fake.quits.isEmpty)
        blocker.noteMediaKey(.playPause)
        fake.time += 1
        fake.launch(-1)
        fake.launch(2, id: "test.other")
        assert(fake.quits.isEmpty)
        fake.launch(3)
        fake.launch(3)
        await settle()
        assert(fake.quits.map(\.processID) == [3])
        assert(fake.replacements == [true])
        fake.launch(4)
        assert(fake.quits.count == 1)
        blocker.noteMediaKey(.next)
        fake.launch(5)
        await settle()
        assert(fake.replacements == [true, false])
        blocker.noteMediaKey(.playPause)
        fake.time += 2.001
        fake.launch(6)
        assert(fake.quits.count == 2)
        blocker.noteMediaKey(.playPause)
        fake.time += 0.5
        fake.gestureAge = 0.1
        fake.launch(7)
        assert(fake.quits.count == 2)
        fake.gestureAge = .infinity
        fake.running = [LastPlayer.appleMusic]
        blocker.noteMediaKey(.playPause)
        fake.running = []
        fake.launch(8)
        assert(fake.quits.count == 2)
        blocker.noteMediaKey(.playPause, at: fake.time - 3)
        fake.launch(9)
        assert(fake.quits.count == 2)
        fake.canQuit = false
        blocker.noteMediaKey(.playPause)
        fake.launch(10)
        await settle()
        assert(blocker.failure == .couldNotQuit && fake.replacements.count == 2)
        blocker.setEnabled(false)
    }

    @MainActor
    static func lifecycle() async {
        let fake = FakeApps()
        let blocker = fake.blocker()
        blocker.setEnabled(true)
        blocker.noteMediaKey(.playPause)
        blocker.setEnabled(false)
        fake.launch(1)
        assert(fake.quits.isEmpty)
        blocker.setEnabled(true)
        fake.launch(2)
        assert(fake.quits.isEmpty)
        blocker.noteMediaKey(.previous)
        fake.launch(3)
        await settle()
        assert(fake.quits.count == 1 && fake.replacements == [false])
        blocker.setEnabled(false)
    }

    @MainActor
    static func cancellation() async {
        let fake = FakeApps()
        var held: CheckedContinuation<Void, Never>?
        var played = false
        let blocker = MusicLaunchBlocker(apps: fake.apps, uptime: { fake.time }, gestureAge: { .infinity }) { _ in
            Task {
                await withCheckedContinuation { held = $0 }
                if !Task.isCancelled { played = true }
            }
        }
        blocker.setEnabled(true)
        blocker.noteMediaKey(.playPause)
        fake.launch(1)
        await settle()
        assert(held != nil)
        blocker.setEnabled(false)
        held?.resume()
        held = nil
        await settle()
        assert(!played)
    }

    @MainActor
    static func live() async throws {
        let apps = PlayerApps.workspace()
        guard !apps.isRunning(LastPlayer.appleMusic) else {
            fatalError("LIVE requires Music to be closed before this opt-in check")
        }
        _ = NSApplication.shared
        var quitTime: ContinuousClock.Instant?
        var observedApps = apps
        observedApps.quit = { launch in
            quitTime = .now
            return apps.quit(launch)
        }
        let blocker = MusicLaunchBlocker(apps: observedApps, openReplacement: { _ in Task {} })
        blocker.setEnabled(true)
        defer { blocker.setEnabled(false) }
        try await openMusic()
        for _ in 0..<20 {
            if apps.isRunning(LastPlayer.appleMusic) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .seconds(1))
        assert(apps.isRunning(LastPlayer.appleMusic))
        print("LIVE open -a Music without a key press: NOT quit")
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: LastPlayer.appleMusic) {
            assert(app.forceTerminate())
        }
        for _ in 0..<30 {
            if !apps.isRunning(LastPlayer.appleMusic) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        assert(!apps.isRunning(LastPlayer.appleMusic))
        blocker.noteMediaKey(.playPause)
        let start = ContinuousClock.now
        try await openMusic()
        try await Task.sleep(for: .milliseconds(900))
        assert(!apps.isRunning(LastPlayer.appleMusic))
        assert(blocker.failure == nil)
        guard let quitTime else { fatalError("LIVE blocker did not observe and quit Music") }
        let elapsed = start.duration(to: quitTime)
        assert(elapsed < .seconds(1))
        print("LIVE Music after noteMediaKey: quit within \(elapsed)")
    }

    @concurrent
    static func openMusic() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Music"]
        let exit = try process.runObservingExit()
        exit.wait()
        assert(process.terminationStatus == 0)
    }
}
