import Foundation

@MainActor
final class LinkQuickFixModule: NotchcastModule {
    private var enabled = false
    private var generation = UUID()
    enum Reachability { case unknown, up, down }
    var state: () -> (paired: Bool, reachability: Reachability) = { (false, .unknown) }
    var choose: ([LinkQuickFixEngine.Action], String?) async -> Int? = { _, _ in nil }
    var execute: (LinkQuickFixEngine.Action) -> Void = { _ in }
    var message: (String) -> Void = { _ in }

    func start() { enabled = true }
    func stop() {
        enabled = false
        generation = UUID()
    }

    func run() async {
        guard enabled else { return }
        let operation = generation
        let current = state()
        let causes: [LinkQuickFixEngine.Cause] = !current.paired ? [.linkExpiring]
            : current.reachability != .up ? [.cableDown, .tailscaleStopped, .dnsFailure] : []
        guard !causes.isEmpty else {
            message(String(localized: "Mac Link is connected.", table: "Notchcast"))
            return
        }
        var offered: [LinkQuickFixEngine.Action] = []
        for cause in causes {
            for action in actions(for: cause, configuration: .init()) where !offered.contains(action) {
                offered.append(action)
            }
        }
        let note = current.paired && current.reachability == .unknown
            ? String(localized: "Mac Link could not be checked yet.", table: "Notchcast") : nil
        guard let index = await choose(offered, note), !Task.isCancelled, enabled,
              generation == operation, offered.indices.contains(index) else { return }
        let latest = state()
        if latest.paired && latest.reachability == .up {
            message(String(localized: "Mac Link is connected.", table: "Notchcast"))
            return
        }
        execute(offered[index])
    }

    func actions(
        for cause: LinkQuickFixEngine.Cause,
        configuration: LinkQuickFixEngine.Configuration
    ) -> [LinkQuickFixEngine.Action] {
        guard enabled else { return [] }
        return LinkQuickFixEngine.actions(for: cause, configuration: configuration)
    }
}
