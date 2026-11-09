// notchcast-sources: Tinycast/Features/CopyPath/Model/*.swift Tinycast/Features/CopyPath/Service/*.swift Tinycast/Features/CopyPath/CopyPathModule*.swift
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
        precondition(module.commandTask == nil)
        precondition(CopyPathModule.launcherCommand.feature == .copyPath)
        print("Verified launcher action resolves with fake reader, copies result and reports success")
    }
}
