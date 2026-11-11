// notchcast-sources: Tinycast/Features/LinkQuickFixes/Model/*.swift Tinycast/Features/LinkQuickFixes/Service/*.swift
// notchcast-sources: Tinycast/Features/LinkQuickFixes/Commands/*.swift
// notchcast-sources: Tinycast/Features/LinkQuickFixes/LinkQuickFixModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
import Foundation

enum NotchcastFeature { case linkQuickFixes }
enum DialogTone { case success }
enum SettingsTab { case notchcast }
enum SettingsAnchor { case notchcastAIUsage }
enum SettingsTarget: Equatable { case section(SettingsAnchor) }
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
@MainActor final class AppCore {
    static let shared = AppCore()
    let settingsCoordinator = Settings()
    var options: [DialogAction] = []
    var defaultIndex = -1
    var dialogMessage: String?
    final class Settings {
        var target: SettingsTarget?
        func showSettings(tab: SettingsTab, revealing: SettingsTarget) { target = revealing }
    }
    func choose(title: String, message: String?, symbol: String?, options: [DialogAction],
                defaultIndex: Int) async -> Int {
        self.options = options
        self.dialogMessage = message
        self.defaultIndex = defaultIndex
        return defaultIndex
    }
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
            .copyCommand("sudo tailscale set --accept-dns=false\nsudo tailscale set --accept-dns=true", cause: .dnsFailure)
        ])
        assert(module.actions(for: .tailscaleStopped, configuration: empty) == [
            .copyCommand("tailscale status\nsudo tailscale up", cause: .tailscaleStopped)
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
        var reachability = LinkQuickFixModule.Reachability.down
        var offered: [LinkQuickFixEngine.Action] = []
        var selected: Int? = nil
        var executed: [LinkQuickFixEngine.Action] = []
        var messages: [String] = []
        module.state = { (paired, reachability) }
        module.choose = { actions, _ in offered = actions; return selected }
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
        reachability = .up
        offered = []
        await module.run()
        assert(offered.isEmpty && messages == ["Mac Link is connected."])
        reachability = .unknown
        module.choose = { actions, note in
            offered = actions
            assert(note == "Mac Link could not be checked yet.")
            return nil
        }
        await module.run()
        assert(offered.count == 3)
        reachability = .down
        let count = executed.count
        module.choose = { _, _ in reachability = .up; return 0 }
        await module.run()
        assert(executed.count == count)
        assert(messages.last == "Mac Link is connected.")
        reachability = .down
        module.choose = { _, _ in reachability = .unknown; return 0 }
        await module.run()
        assert(executed.count == count + 1)
        module.choose = { _, _ in paired = false; return 0 }
        await module.run()
        assert(executed.count == count + 2)
        module.choose = { _, _ in module.stop(); module.start(); return 0 }
        await module.run()
        assert(executed.count == count + 2)
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
        let entries = LinkQuickFixModule.register(AppCore.shared)
        assert(entries.count == 1 && entries[0].module === LinkQuickFixModule.shared)
        assert(entries[0].requires == [.linkQuickFixes] && entries[0].requiresAny.isEmpty)
        let live = LinkQuickFixModule().configure()
        live.start()
        var link: (paired: Bool, reachability: LinkQuickFixModule.Reachability) = (true, .down)
        live.state = { link }
        live.execute = { _ in assertionFailure("Cancel executed an action") }
        await live.run()
        assert(AppCore.shared.options.count == 4 && AppCore.shared.defaultIndex == 3)
        assert(AppCore.shared.options.last?.role == .cancel)
        assert(AppCore.shared.options.map(\.title) == ["Open Network Settings",
            "Copy Tailscale Command", "Copy DNS Reset Command", "Cancel"])
        link.reachability = .unknown
        await live.run()
        assert(AppCore.shared.dialogMessage == "Mac Link could not be checked yet.")
        link.paired = false
        await live.run()
        assert(AppCore.shared.options.map(\.title) == ["Open Mac Link Settings", "Cancel"])
        let relink = LinkQuickFixModule().configure()
        relink.execute(.relinkInConnections)
        assert(AppCore.shared.settingsCoordinator.target == .section(.notchcastAIUsage))
        _ = await live.choose([.copyCommand("sync")], nil)
        assert(AppCore.shared.options.first?.title == "Copy Sync Command")
        print("Review cases: cause labels, registration entry, unknown/unpaired/up, settings target, dialog state changes passed")
        print("Link quick fixes: down offers 3, unpaired relinks, up reports connected, Cancel runs nothing")
        print("Link quick fixes: all executor effects and production dialog default passed")
        print("Link quick fixes: all cause mappings, configuration validation and lifecycle gates passed")
    }
}
