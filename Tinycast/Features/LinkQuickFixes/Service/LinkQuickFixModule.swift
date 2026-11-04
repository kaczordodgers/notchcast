@MainActor
final class LinkQuickFixModule: NotchcastModule {
    private var enabled = false

    func start() { enabled = true }
    func stop() { enabled = false }

    func actions(
        for cause: LinkQuickFixEngine.Cause,
        configuration: LinkQuickFixEngine.Configuration
    ) -> [LinkQuickFixEngine.Action] {
        guard enabled else { return [] }
        return LinkQuickFixEngine.actions(for: cause, configuration: configuration)
    }
}
