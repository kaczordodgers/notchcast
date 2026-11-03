// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/Soloist*.swift
// notchcast-sources: Tinycast/Features/Music/Service/Soloist*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Platform/NotificationToken.swift
import AppKit
import Foundation

private func check(_ condition: Bool, _ message: String = "check failed", line: UInt = #line) {
    precondition(condition, "\(message), line \(line)")
}

@main
struct SoloistSpeakerTest {
    @MainActor
    static func main() async throws {
        try await statesAndKey()
        try await backoff()
        try await peers()
        try await expiry()
        try await staleWork()
        try await failedInstall()
        try await previousOwnedProcess()
        try await termination()
        print("PASS: speaker states, 1/2/4/8 restart, five-start limit, healthy reset, expiry retry, "
              + "one-soloist guard, wake, cancellation")
    }

    @MainActor
    private static func statesAndKey() async throws {
        let f = try Fixture()
        check(f.speaker.state == .off && f.launcher.children.isEmpty)
        f.secret = nil
        f.speaker.setEnabled(true)
        check(f.speaker.state == .noKey)
        try f.key.save("fixture-key")
        await f.settle()
        check(f.launcher.children.count == 1)
        let arguments = f.launcher.arguments[0]
        check(arguments == f.files.arguments(key: "fixture-key", deviceName: "Notchcast"))
        try f.answer()
        check(f.speaker.state == .running(port: 51234))
        check(f.ports == [51234])
        f.speaker.setEnabled(true)
        await f.settle()
        check(f.launcher.children.count == 1)
        try f.key.remove()
        check(f.speaker.state == .noKey && f.ports == [51234, nil])
        try f.key.save("replacement-key")
        await f.settle()
        check(f.launcher.arguments.last?.contains("replacement-key") == true)
        f.speaker.setEnabled(false)
        check(f.speaker.state == .off && f.clock.pending == 0)
        check(f.launcher.children.allSatisfy(\.stopped))

        let missing = try Fixture()
        missing.builds.available = []
        missing.speaker.setEnabled(true)
        await missing.settle()
        check(missing.speaker.state == .needsBuild && missing.builds.installs == 0)
        missing.speaker.installBuild()
        await missing.settle()
        check(missing.builds.installs == 1 && missing.launcher.children.count == 1)
    }

    @MainActor
    private static func backoff() async throws {
        let f = try Fixture()
        f.speaker.setEnabled(true)
        await f.settle()
        for delay in [1.0, 2, 4, 8] {
            let count = f.launcher.children.count
            f.launcher.crash()
            f.clock.advance(delay - 0.01)
            await f.settle()
            check(f.launcher.children.count == count)
            f.clock.advance(0.01)
            await f.settle()
            check(f.launcher.children.count == count + 1)
        }
        f.launcher.crash()
        check(f.speaker.state == .failed(reason: .process))
        f.clock.advance(3_600)
        await f.settle()
        check(f.launcher.children.count == 5)
        f.speaker.recheckAfterWake()
        await f.settle()
        check(f.launcher.children.count == 5)
        f.speaker.setEnabled(false)
        f.speaker.setEnabled(true)
        await f.settle()
        check(f.launcher.children.count == 6)
        f.launcher.crash()
        f.clock.advance(1)
        await f.settle()
        try f.answer()
        f.clock.advance(600)
        f.launcher.crash()
        f.clock.advance(1)
        await f.settle()
        check(f.launcher.children.count == 8)

        let deadline = try Fixture()
        try deadline.files.makeFolders()
        try Data("41234".utf8).write(to: deadline.files.portFile)
        deadline.speaker.setEnabled(true)
        await deadline.settle()
        check(deadline.speaker.port == nil)
        deadline.clock.advance(10)
        check(deadline.launcher.children[0].stopped)
        deadline.clock.advance(1)
        await deadline.settle()
        check(deadline.launcher.children.count == 2)
    }

    @MainActor
    private static func peers() async throws {
        let f = try Fixture()
        let other = SoloistPeer(pid: 42, path: "/another/soloist")
        f.processes.list = [other]
        f.speaker.setEnabled(true)
        await f.settle()
        check(f.speaker.state == .waitingForOther && f.launcher.children.isEmpty)
        check(f.clock.pending == 0 && f.processes.stopped.isEmpty)
        f.processes.end(42)
        f.clock.advance(1)
        await f.settle()
        try f.answer()
        f.processes.list = [.init(pid: f.launcher.children[0].pid, path: f.builds.available[0].executable.path)]
        f.speaker.lookForOthers()
        check(f.speaker.state == .running(port: 51234) && !f.launcher.children[0].stopped)
        f.processes.list = []
        f.probeAnswer = true
        f.speaker.recheckAfterWake()
        await f.settle()
        check(f.launcher.children.count == 1)
        f.probeAnswer = false
        f.speaker.recheckAfterWake()
        await f.settle()
        check(f.launcher.children.count == 2)
        try f.answer()
        f.processes.list = [other]
        f.speaker.lookForOthers()
        check(f.speaker.state == .waitingForOther && f.launcher.children.last?.stopped == true)
        check(f.processes.stopped.isEmpty)

        let stale = try Fixture()
        let own = SoloistPeer(pid: 77, path: stale.builds.available[0].executable.path)
        stale.processes.list = [own]
        try stale.files.makeFolders()
        stale.speaker.setEnabled(true)
        check(stale.processes.stopped == [own] && stale.launcher.children.isEmpty)
        stale.processes.end(77)
        stale.clock.advance(1)
        await stale.settle()
        check(stale.launcher.children.count == 1)

        let unowned = try Fixture()
        unowned.processes.list = [.init(pid: 78, path: unowned.builds.available[0].executable.path)]
        try unowned.files.makeFolders()
        unowned.speaker.setEnabled(true)
        check(unowned.processes.stopped == unowned.processes.list && unowned.speaker.state == .waitingForOther)
        let reused = try Fixture()
        try reused.files.makeFolders()
        reused.processes.list = [other]
        reused.speaker.setEnabled(true)
        check(reused.processes.stopped.isEmpty)
    }

    @MainActor
    private static func expiry() async throws {
        let f = try Fixture()
        let now = f.now()
        f.builds.available = (0..<3).map { index in
            SoloistBuild(executable: f.files.builds.appending(path: "build\(index)/soloist"), version: "fixture-\(index)",
                         built: now.addingTimeInterval(-Double(84 + index) * 86_400))
        }
        f.speaker.setEnabled(true)
        await f.settle()
        try f.answer()
        check(f.speaker.state == .expiresSoon(days: 6))
        f.launcher.crash(status: 10)
        f.clock.advance(0)
        await f.settle()
        check(f.launcher.children.count == 2 && f.builds.installs == 0)
        f.launcher.crash(status: 10)
        f.clock.advance(3_599)
        await f.settle()
        check(f.launcher.children.count == 2)
        f.clock.advance(1)
        await f.settle()
        check(f.launcher.children.count == 3)
        f.launcher.crash(status: 10)
        f.clock.advance(7_200)
        await f.settle()
        check(f.speaker.state == .needsBuild && f.builds.installs == 0)

        let timed = try Fixture()
        timed.builds.available = [.init(executable: timed.files.builds.appending(path: "timed/soloist"), version: "timed",
                                       built: timed.now().addingTimeInterval(-SoloistBuild.lifetime + 2))]
        timed.speaker.setEnabled(true)
        await timed.settle()
        try timed.answer()
        timed.clock.advance(2)
        await timed.settle()
        timed.clock.advance(0)
        await timed.settle()
        check(timed.launcher.children[0].stopped && timed.speaker.state == .needsBuild)
    }

    @MainActor
    private static func staleWork() async throws {
        let f = try Fixture()
        f.builds.holdLookup = true
        f.speaker.setEnabled(true)
        await f.yieldUntil { f.builds.lookup != nil }
        f.speaker.setEnabled(false)
        f.builds.lookup?.resume(returning: f.builds.available.first)
        f.builds.lookup = nil
        await f.settle()
        check(f.speaker.state == .off && f.launcher.children.isEmpty)

        let update = try Fixture()
        update.speaker.setEnabled(true)
        await update.settle()
        try update.answer()
        update.builds.holdInstall = true
        update.speaker.installBuild()
        await update.yieldUntil { update.builds.installation != nil }
        update.speaker.setEnabled(false)
        update.builds.installation?.resume(returning: update.builds.newBuild)
        update.builds.installation = nil
        await update.settle()
        check(update.speaker.state == .off && update.launcher.children.count == 1)

        let exitUpdate = try Fixture()
        exitUpdate.speaker.setEnabled(true)
        await exitUpdate.settle()
        try exitUpdate.answer()
        exitUpdate.builds.holdInstall = true
        exitUpdate.speaker.installBuild()
        await exitUpdate.yieldUntil { exitUpdate.builds.installation != nil }
        exitUpdate.launcher.crash(status: 10)
        check(exitUpdate.speaker.installing?.isCancelled == false)
        exitUpdate.builds.installation?.resume(returning: exitUpdate.builds.newBuild)
        exitUpdate.builds.installation = nil
        exitUpdate.clock.advance(1)
        await exitUpdate.settle()
        check(exitUpdate.launcher.children.count == 2 && exitUpdate.speaker.state == .starting)

        let race = try Fixture()
        race.builds.holdLookup = true
        race.speaker.setEnabled(true)
        await race.yieldUntil { race.builds.lookup != nil }
        race.processes.list = [.init(pid: 55, path: "/late/soloist")]
        race.builds.lookup?.resume(returning: race.builds.available.first)
        race.builds.lookup = nil
        await race.settle()
        check(race.speaker.state == .waitingForOther && race.launcher.children.isEmpty)
    }

    @MainActor
    private static func failedInstall() async throws {
        let f = try Fixture()
        f.speaker.setEnabled(true)
        await f.settle()
        f.launcher.crash()
        f.builds.installError = .download
        f.speaker.installBuild()
        await f.settle()
        check(f.speaker.installFailure == .download && f.launcher.children.count == 2)
        try f.answer()
        f.speaker.installBuild()
        await f.settle()
        check(f.speaker.installFailure == .download && f.speaker.state == .running(port: 51234))
    }

    @MainActor
    private static func previousOwnedProcess() async throws {
        let f = try Fixture()
        let previous = SoloistPeer(pid: 123, path: f.builds.available[0].executable.path)
        f.processes.list = [previous]
        check(!FileManager.default.fileExists(atPath: f.files.root.appending(path: "notchcast-soloist.pid").path))
        f.speaker.setEnabled(true)
        check(f.processes.stopped == [previous] && f.speaker.state == .waitingForOther)
        f.processes.end(previous.pid)
        f.clock.advance(1)
        await f.settle()
        check(f.launcher.children.count == 1)
    }

    @MainActor
    private static func termination() async throws {
        let f = try Fixture()
        f.speaker.setEnabled(true)
        await f.settle()
        check(!FileManager.default.fileExists(atPath: f.files.root.appending(path: "notchcast-soloist.pid").path))
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        check(f.launcher.children[0].stopped)
        check(f.speaker.state == .off)
    }

    @MainActor
    final class Fixture {
        let files: SoloistFiles
        let clock = Clock()
        let launcher = Launcher()
        let processes = Processes()
        let builds: Builds
        var secret: String? = "fixture-key"
        var ports: [Int?] = []
        var probeAnswer = true
        lazy var key = SoloistKey(read: { [unowned self] in self.secret }, write: { [unowned self] in self.secret = $0 })
        lazy var speaker = SoloistSpeaker(key: key, files: files, builds: builds, launcher: launcher, processes: processes,
            schedule: clock.schedule, now: { [unowned self] in self.now() }, probe: { [unowned self] _ in self.probeAnswer },
            watch: SoloistSystemEvents.watch)

        init() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "soloist-speaker-\(UUID().uuidString)")
            files = SoloistFiles(root: root)
            builds = Builds(build: .init(executable: files.builds.appending(path: "fixture/soloist"), version: "fixture",
                                        built: Date(timeIntervalSince1970: 2_000_000_000)))
            speaker.onPort = { [weak self] in self?.ports.append($0) }
        }

        func now() -> Date { Date(timeIntervalSince1970: 2_000_000_000 + clock.time) }

        func answer() throws {
            try files.makeFolders()
            try Data("51234".utf8).write(to: files.portFile)
            try Data("127.0.0.1".utf8).write(to: files.addressFile)
            clock.advance(0.25)
        }

        func settle() async {
            for _ in 0..<6 {
                await speaker.preparing?.value
                await speaker.installing?.value
                await speaker.checking?.value
                await Task.yield()
            }
        }

        func yieldUntil(_ condition: () -> Bool) async {
            for _ in 0..<100 where !condition() { await Task.yield() }
            check(condition(), "task did not reach seam")
        }

        isolated deinit {
            speaker.setEnabled(false)
            try? FileManager.default.removeItem(at: files.root)
        }
    }

    @MainActor
    final class Clock {
        var time: TimeInterval = 0
        var work: [UUID: (TimeInterval, @MainActor () -> Void)] = [:]
        var pending: Int { work.count }
        var schedule: SoloistSchedule {
            SoloistSchedule(now: { [unowned self] in self.time }, after: { [unowned self] delay, action in
                let id = UUID()
                self.work[id] = (self.time + delay, action)
                return SoloistCancellation { [weak self] in self?.work[id] = nil }
            })
        }

        func advance(_ seconds: TimeInterval) {
            let target = time + seconds
            while let next = work.filter({ $0.value.0 <= target }).min(by: { $0.value.0 < $1.value.0 }) {
                time = next.value.0
                work[next.key] = nil
                next.value.1()
            }
            time = target
        }
    }

    @MainActor
    final class Builds: SoloistBuildSource {
        var available: [SoloistBuild]
        var newBuild: SoloistBuild
        var installs = 0
        var holdLookup = false
        var holdInstall = false
        var installError: SoloistFailure?
        var lookup: CheckedContinuation<SoloistBuild?, Never>?
        var installation: CheckedContinuation<SoloistBuild, Never>?

        init(build: SoloistBuild) { available = [build]; newBuild = build }

        func installed(excluding: Set<URL>) async throws -> SoloistBuild? {
            if holdLookup { return await withCheckedContinuation { lookup = $0 } }
            return available.first { !excluding.contains($0.executable) }
        }

        func install() async throws -> SoloistBuild {
            installs += 1
            if let installError { throw installError }
            if holdInstall { return await withCheckedContinuation { installation = $0 } }
            available = [newBuild]
            return newBuild
        }
    }

    @MainActor
    final class Child: SoloistChild {
        let pid: Int32
        let exit: @MainActor (Int32) -> Void
        var stopped = false
        init(pid: Int32, exit: @escaping @MainActor (Int32) -> Void) { self.pid = pid; self.exit = exit }
        func stop() {
            guard !stopped else { return }
            stopped = true
            exit(0)
        }
    }

    @MainActor
    final class Launcher: SoloistLauncher {
        var children: [Child] = []
        var arguments: [[String]] = []
        func launch(_ executable: URL, arguments: [String],
                    onExit: @escaping @MainActor (Int32) -> Void) throws -> any SoloistChild {
            self.arguments.append(arguments)
            let child = Child(pid: Int32(9_000 + children.count), exit: onExit)
            children.append(child)
            return child
        }
        func crash(status: Int32 = 1) {
            children.last?.stopped = true
            children.last?.exit(status)
        }
    }

    @MainActor
    final class Processes: SoloistProcessList {
        var list: [SoloistPeer] = []
        var stopped: [SoloistPeer] = []
        var watches: [UUID: (Int32, @MainActor () -> Void)] = [:]
        func soloists() -> [SoloistPeer] { list }
        func stop(_ peer: SoloistPeer) { stopped.append(peer) }
        func watchExit(of pid: Int32, _ onExit: @escaping @MainActor () -> Void) -> SoloistCancellation {
            let id = UUID()
            watches[id] = (pid, onExit)
            return SoloistCancellation { [weak self] in self?.watches[id] = nil }
        }
        func end(_ pid: Int32) {
            list.removeAll { $0.pid == pid }
            let callbacks = watches.filter { $0.value.0 == pid }
            for (id, callback) in callbacks {
                watches[id] = nil
                callback.1()
            }
        }
    }
}
