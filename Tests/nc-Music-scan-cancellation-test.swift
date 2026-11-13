// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/Soloist*.swift
// notchcast-sources: Tinycast/Features/Music/Service/Soloist*.swift Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
import Foundation

@MainActor
private final class CancelledBuilds: SoloistBuildSource {
    func installed(excluding: Set<URL>) async throws -> SoloistBuild? { throw CancellationError() }
    func install() async throws -> SoloistBuild { throw CancellationError() }
}

@MainActor
private final class NoLauncher: SoloistLauncher {
    func launch(_ executable: URL, arguments: [String], onExit: @escaping @MainActor (Int32) -> Void) throws -> any SoloistChild {
        fatalError("Scan must not launch")
    }
}

@MainActor
private final class NoProcesses: SoloistProcessList {
    func soloists() -> [SoloistPeer] { [] }
    func stop(_ peer: SoloistPeer) {}
    func watchExit(of pid: Int32, _ onExit: @escaping @MainActor () -> Void) -> SoloistCancellation {
        SoloistCancellation {}
    }
}

@main
struct ScanCancellationTest {
    @MainActor
    static func main() async {
        let key = SoloistKey(read: { nil }, write: { _ in })
        let speaker = SoloistSpeaker(key: key, builds: CancelledBuilds(), launcher: NoLauncher(), processes: NoProcesses())
        await speaker.refreshInstalledBuild()
        precondition(speaker.installFailure == nil, "Cancelled scan must not become a filesystem failure")
        print("PASS: cancelled scan leaves installation failure clear")
    }
}
