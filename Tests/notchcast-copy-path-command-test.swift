// notchcast-sources: Tinycast/Features/Launcher/CopyPath/Model/*.swift Tinycast/Features/Launcher/CopyPath/Service/*.swift Tinycast/Features/Launcher/CopyPath/CopyPathModule*.swift
import Foundation

@MainActor protocol NotchcastModule {}
enum NotchcastFeature { case copyPath }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor enum NotchcastCore { static let copyPath = CopyPathModule() }
@MainActor final class AppCore {
    enum Tone { case neutral }
    static let shared = AppCore()
    func showMessage(_ text: String, tone: Tone) {}
}
@main struct CopyTests {
    @MainActor static func main() async {
        let module = CopyPathModule(makeService: { CopyPathService { request in
            precondition(request == .finderSelection)
            return ["/test/file"]
        } })
        module.start()
        var copied = ""
        var reported = ""
        module.copyFromLauncher(target: CopyPathTarget(processID: 1, bundleID: "com.apple.finder"),
                                home: "/test", copy: { copied = $0; return true }, report: { reported = $0 })
        await module.commandTask?.value
        precondition(copied == "~/file" && reported == "Copied path")
        module.stop()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let pending = CopyPathModule(makeService: { CopyPathService { _ in
            for await _ in gate { break }
            return ["/test/late"]
        } })
        pending.start()
        var lateCopied = false
        pending.copyFromLauncher(target: CopyPathTarget(processID: 1, bundleID: "com.apple.finder"),
                                 home: "/test", copy: { _ in lateCopied = true; return true }, report: { _ in lateCopied = true })
        let task = pending.commandTask
        pending.stop()
        release.yield()
        await task?.value
        precondition(!lateCopied)
        print("Verified launcher action resolves with fake reader, copies result and reports success; a stopped module copies nothing")
    }
}
