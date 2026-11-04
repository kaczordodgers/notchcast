// notchcast-sources: Tinycast/Features/LinkQuickFixes/Model/*.swift Tinycast/Features/LinkQuickFixes/Service/*.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@main
struct LinkQuickFixTests {
    @MainActor
    static func main() {
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
        print("Link quick fixes: all cause mappings, configuration validation and lifecycle gates passed")
    }
}
