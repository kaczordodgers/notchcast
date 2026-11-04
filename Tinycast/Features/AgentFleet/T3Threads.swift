import Foundation

@MainActor
final class T3Threads: WaitingThreadSource, FleetThreadSource, AgentIslandSource {
    private struct Unavailable: LocalizedError {
        var errorDescription: String? { String(localized: "T3 Threads unavailable") }
    }

    let module: T3ThreadsModule

    init(_ module: T3ThreadsModule) { self.module = module }

    private func available() throws -> [T3Thread] {
        guard module.isRunning else { throw Unavailable() }
        if let error = module.error { throw error }
        return module.threads
    }

    func readWaitingThreads(in folder: URL) async throws -> [WaitingThread] {
        try available().compactMap { thread in
            guard [.waiting_for_approval, .waiting_for_input].contains(thread.phase) else { return nil }
            return WaitingThread(id: thread.id, title: thread.title ?? thread.id,
                kind: thread.phase == .waiting_for_approval ? .approval : .question)
        }
    }

    func read(_ destination: FleetSnapshot.Destination) async throws -> FleetSnapshot {
        guard destination.route == .local else { throw FleetSnapshot.Failure.linkExpired }
        let threads = try available().map { thread in
            FleetSnapshot.Thread(id: thread.id, title: thread.title ?? thread.id, project: "",
                engine: thread.model ?? "", state: Self.state(thread),
                began: thread.updatedDate ?? .distantPast,
                ended: [.completed, .failed].contains(thread.phase) ? thread.updatedDate : nil,
                parentID: nil, workspacePath: nil)
        }
        return FleetSnapshot(threads: threads, report: nil, limits: nil)
    }

    private static func state(_ thread: T3Thread) -> FleetSnapshot.State {
        switch thread.phase {
        case .waiting_for_approval, .waiting_for_input: .waiting
        case .starting, .running: .working
        case .completed, .failed, .stale: .finished
        }
    }

    var snapshot: AgentIslandState.Snapshot {
        guard let threads = try? available() else {
            return .init(sourceID: "t3", failureID: "T3 Threads unavailable")
        }
        return .init(sourceID: "t3", running: threads.filter {
            [.starting, .running].contains($0.phase)
        }.map { $0.title ?? $0.id },
            questions: threads.filter { $0.phase == .waiting_for_input }.count,
            approvals: threads.filter { $0.phase == .waiting_for_approval }.count)
    }
}
