import Foundation

@MainActor
enum FleetLocalSource {
    static func read() async -> FleetSnapshot {
        await read(state: AgentThreadsModule.shared.state,
                   enabled: { NotchcastPreferences.shared.isOn(.agentThreads) })
    }

    static func read(state: AgentThreadsState, enabled: @MainActor () -> Bool) async -> FleetSnapshot {
        guard enabled() else { return .init(rows: [], failure: .off) }
        if state.status != .loading { state.refresh() }
        repeat {
            await state.waitUntilIdle()
            guard !Task.isCancelled else { return .init(rows: [], failure: .failed) }
            guard enabled() else { return .init(rows: [], failure: .off) }
        } while state.status == .loading
        guard state.status == .ready else { return .init(rows: [], failure: .failed) }
        let rows = state.threads.filter { $0.phase != .stale }.map { thread in
            FleetSnapshot.Row(id: thread.id, title: thread.title, project: thread.project,
                model: thread.model, phase: thread.phase.waiting ? .waiting
                    : (thread.phase.finished ? .finished : .working),
                pendingCount: thread.pendingCount, link: thread.link, updatedAt: thread.updatedAt)
        }
        return .init(rows: rows, failure: nil)
    }
}
