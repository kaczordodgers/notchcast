// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/Soloist*.swift
// notchcast-sources: Tinycast/Features/Music/Service/Soloist*.swift Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
import Foundation

@MainActor
private final class Builds: SoloistBuildSource {
    let build: SoloistBuild
    var installation: CheckedContinuation<SoloistBuild, any Error>?
    init(_ root: URL) {
        build = SoloistBuild(executable: root.appending(path: "soloist"), version: "test", built: Date())
    }
    func installed(excluding: Set<URL>) async throws -> SoloistBuild? { build }
    func install() async throws -> SoloistBuild {
        try await withCheckedThrowingContinuation { installation = $0 }
    }
}

@MainActor
private final class Child: SoloistChild {
    let pid: Int32 = 12345
    var stopped = false
    func stop() { stopped = true }
}

@MainActor
private final class Launcher: SoloistLauncher {
    let child = Child()
    func launch(_ executable: URL, arguments: [String], onExit: @escaping @MainActor (Int32) -> Void) throws -> any SoloistChild {
        child
    }
}

@MainActor
private final class Processes: SoloistProcessList {
    func soloists() -> [SoloistPeer] { [] }
    func stop(_ peer: SoloistPeer) {}
    func watchExit(of pid: Int32, _ onExit: @escaping @MainActor () -> Void) -> SoloistCancellation { SoloistCancellation {} }
}

@main
struct DownloadLifecycleTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SoloistFiles(root: root)
        let builds = Builds(root)
        let launcher = Launcher()
        var callbacks: [@MainActor () -> Void] = []
        var probes = 0
        let schedule = SoloistSchedule(now: { 0 }, after: { _, callback in
            callbacks.append(callback)
            return SoloistCancellation {}
        })
        let key = SoloistKey(read: { "fixture-key" }, write: { _ in })
        let speaker = SoloistSpeaker(key: key, files: files, builds: builds, launcher: launcher,
            processes: Processes(), schedule: schedule, probe: { _ in probes += 1; return true },
            watch: { _, _, _ in SoloistCancellation {} })
        speaker.setEnabled(true)
        await speaker.preparing?.value
        try Data("51234".utf8).write(to: files.portFile)
        try Data("127.0.0.1".utf8).write(to: files.addressFile)
        callbacks.removeFirst()()
        precondition(speaker.port == 51234)
        speaker.installBuild()
        while builds.installation == nil { await Task.yield() }
        speaker.recheckAfterWake()
        await speaker.checking?.value
        precondition(speaker.state == .downloading && probes == 0 && !launcher.child.stopped,
                     "Wake must not overwrite or disrupt an in-flight download")
        speaker.setEnabled(false)
        builds.installation?.resume(returning: builds.build)
        print("PASS: wake preserves the active download")
    }
}
