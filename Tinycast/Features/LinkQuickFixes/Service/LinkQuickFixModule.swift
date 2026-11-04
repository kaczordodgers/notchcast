import Foundation

@MainActor
final class LinkQuickFixModule: NotchcastModule {
    private var enabled = false
    private var generation = UUID()
    var state: () -> (paired: Bool, down: Bool) = { (true, false) }
    var choose: ([LinkQuickFixEngine.Action]) async -> Int? = { _ in nil }
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
            : current.down ? [.cableDown, .tailscaleStopped, .dnsFailure] : []
        guard !causes.isEmpty else {
            message(String(localized: "Mac Link is connected."))
            return
        }
        var offered: [LinkQuickFixEngine.Action] = []
        for cause in causes {
            for action in actions(for: cause, configuration: .init()) where !offered.contains(action) {
                offered.append(action)
            }
        }
        guard let index = await choose(offered), !Task.isCancelled, enabled, generation == operation,
              state() == current, offered.indices.contains(index) else { return }
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
