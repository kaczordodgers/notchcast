@MainActor
final class AgentIslandModule: NotchcastModule {
    private(set) var state = AgentIslandState()
    private(set) var isRunning = false
    var sources: [any AgentIslandSource] = []
    var handleAction: (AgentIslandAction) -> Void = { _ in }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        state = AgentIslandState()
    }

    @discardableResult
    func refresh(now: Double, pointerInside: Bool) -> Bool {
        guard isRunning else { return false }
        return state.reduce(sources.map(\.snapshot), now: now, pointerInside: pointerInside)
    }

    func route(_ action: AgentIslandAction) {
        guard isRunning, sources.contains(where: { $0.snapshot.sourceID == action.sourceID }) else { return }
        if action.kind == .dismissFailure { state.dismissFailure(sourceID: action.sourceID) }
        handleAction(action)
    }
}
