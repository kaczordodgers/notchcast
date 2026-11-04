// notchcast-sources: Tinycast/Features/LinkQuickFixes/Model/*.swift Tinycast/Features/LinkQuickFixes/Service/*.swift
// notchcast-sources: Tinycast/Features/LinkQuickFixes/Commands/*.swift
import Foundation

enum NotchcastFeature { case linkQuickFixes }
enum SettingsTab { case notchcast }
enum SettingsTarget { case notchcastSystem }
struct NotchcastCommand: Sendable {
    var slug: String
    var name: String
    var sfSymbol: String
    var feature: NotchcastFeature
    var isEnabled: @MainActor @Sendable () -> Bool
    var run: @MainActor @Sendable () -> Void
}
struct DialogAction {
    enum Role { case standard, cancel }
    var title: String
    var role: Role = .standard
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor enum NotchcastCore {
    static let linkQuickFixes = LinkQuickFixModule()
    static let macLink = Pairing()
    static let linkHealth = Health()
    final class Pairing { var isPaired = true }
    final class Health {
        var health = State()
        struct State {
            enum Reachability { case up, down }
            var reachability = Reachability.up
        }
    }
}
@MainActor final class AppCore {
    static let shared = AppCore()
    let settingsCoordinator = Settings()
    var options: [DialogAction] = []
    var defaultIndex = -1
    final class Settings {
        func showSettings(tab: SettingsTab, revealing: SettingsTarget) {}
    }
    func showMessage(_ message: String) {}
    func choose(title: String, message: String?, symbol: String?, options: [DialogAction],
                defaultIndex: Int) async -> Int {
        self.options = options
        self.defaultIndex = defaultIndex
        return defaultIndex
    }
}

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@main
struct LinkQuickFixTests {
    @MainActor
    static func main() async {
        let empty = LinkQuickFixEngine.Configuration()
        let module = LinkQuickFixModule()
        assert(module.actions(for: .dnsFailure, configuration: empty).isEmpty)
        module.start()
        assert(module.actions(for: .dnsFailure, configuration: empty) == [
            .copyCommand("sudo tailscale set --accept-dns=false\nsudo tailscale set --accept-dns=true")
        ])
        assert(module.actions(for: .tailscaleStopped, configuration: empty) == [
            .copyCommand("tailscale status\nsudo tailscale up")
        ])
        assert(module.actions(for: .mirrorStale, configuration: empty).isEmpty)
        let log = URL(fileURLWithPath: "/tmp/link-fix-fixture/sync.log")
        let configured = LinkQuickFixEngine.Configuration(mirrorSyncCommand: "manual-sync", mirrorLog: log)
        assert(module.actions(for: .mirrorStale, configuration: configured) == [
            .copyCommand("manual-sync"), .openMirrorLog(log)
        ])
        let invalid = LinkQuickFixEngine.Configuration(
            mirrorSyncCommand: " \n", mirrorLog: URL(string: "https://example.com/log"))
        assert(module.actions(for: .mirrorStale, configuration: invalid).isEmpty)
        assert(module.actions(for: .cableDown, configuration: empty) == [.openNetworkSettings])
        assert(module.actions(for: .linkExpiring, configuration: empty) == [.relinkInConnections])
        module.stop()
        for cause in LinkQuickFixEngine.Cause.allCases {
            assert(module.actions(for: cause, configuration: configured).isEmpty)
        }
        module.start()
        var paired = true
        var down = true
        var offered: [LinkQuickFixEngine.Action] = []
        var selected: Int? = nil
        var executed: [LinkQuickFixEngine.Action] = []
        var messages: [String] = []
        module.state = { (paired, down) }
        module.choose = { offered = $0; return selected }
        module.execute = { executed.append($0) }
        module.message = { messages.append($0) }
        await module.run()
        assert(offered.count == 3 && executed.isEmpty)
        for index in 0..<3 {
            selected = index
            await module.run()
            assert(executed.last == offered[index])
        }
        paired = false
        selected = 0
        await module.run()
        assert(offered == [.relinkInConnections] && executed.last == .relinkInConnections)
        paired = true
        down = false
        offered = []
        await module.run()
        assert(offered.isEmpty && messages == ["Mac Link is connected."])
        down = true
        let count = executed.count
        module.choose = { _ in down = false; return 0 }
        await module.run()
        assert(executed.count == count)
        down = true
        module.choose = { _ in module.stop(); module.start(); return 0 }
        await module.run()
        assert(executed.count == count)
        var copied: [String] = []
        var opened: [URL] = []
        var settings = 0
        let executor = LinkQuickFixExecutor(copy: { copied.append($0) }, open: { opened.append($0) },
            settings: { settings += 1 }, message: { messages.append($0) })
        executor.run(.copyCommand("fixture"))
        executor.run(.openNetworkSettings)
        executor.run(.relinkInConnections)
        executor.run(.openMirrorLog(log))
        assert(copied == ["fixture"] && messages.last == "Command copied.")
        assert(opened == [URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!, log])
        assert(settings == 1)
        let live = LinkQuickFixModule().configure()
        live.start()
        NotchcastCore.linkHealth.health.reachability = .down
        live.execute = { _ in assertionFailure("Cancel executed an action") }
        await live.run()
        assert(AppCore.shared.options.count == 4 && AppCore.shared.defaultIndex == 3)
        assert(AppCore.shared.options.last?.role == .cancel)
        print("Link quick fixes: down offers 3, unpaired relinks, up reports connected, Cancel runs nothing")
        print("Link quick fixes: all executor effects and production dialog default passed")
        print("Link quick fixes: all cause mappings, configuration validation and lifecycle gates passed")
    }
}
