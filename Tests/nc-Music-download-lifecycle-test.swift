// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/Soloist*.swift
// notchcast-sources: Tinycast/Features/Music/Service/Soloist*.swift Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Features/Music/Settings/SpotifySettingsCoordinator.swift
// notchcast-sources: Tinycast/Features/Music/Settings/SoloistFailure+Settings.swift
import Foundation

@MainActor
final class AppCore {
    enum Tone { case danger }
    var messages: [String] = []
    func showMessage(_ text: String, tone: Tone? = nil) { messages.append(text) }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
    func reportFailure(title: String, message: String, symbol: String, recovery: String?) async {}
}

@MainActor
final class SpotifyConnectModule {
    let speaker: SoloistSpeaker
    let key: SoloistKey
    var isEnabled = true
    init(speaker: SoloistSpeaker, key: SoloistKey) {
        self.speaker = speaker
        self.key = key
    }
}

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
        let core = AppCore()
        let module = SpotifyConnectModule(speaker: speaker, key: key)
        let coordinator = SpotifySettingsCoordinator(module: module, core: core)
        coordinator.installBuild()
        let feedback = coordinator.download
        let installation = speaker.installing
        while builds.installation == nil { await Task.yield() }
        speaker.recheckAfterWake()
        await speaker.checking?.value
        precondition(speaker.state == .downloading && probes == 0 && !launcher.child.stopped,
                     "Wake must not overwrite or disrupt an in-flight download")
        speaker.setEnabled(false)
        builds.installation?.resume(returning: builds.build)
        let installed = await installation?.value
        await feedback?.value
        precondition(installed == false && speaker.build == builds.build,
                     "Cancelled download must not report success just because an old build exists")
        precondition(core.messages.isEmpty, "Cancelled download must not show a success HUD")
        print("PASS: wake preserves the download; cancelled installation reports no success")
    }
}
