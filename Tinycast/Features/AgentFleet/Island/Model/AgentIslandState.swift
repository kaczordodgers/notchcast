struct AgentIslandState: Sendable {
    enum Mode: Int, Sendable, CaseIterable {
        case idle, working, message, takeover, question, approval, failed
    }

    struct Presentation: Equatable, Sendable {
        var mode: Mode = .idle
        var agents: [String] = []
        var remaining = 0
        var unreadCount = 0
        var latest: String?
        var finished = false
        var peek = false
    }

    struct Snapshot: Equatable, Sendable {
        let sourceID: String
        var running: [String] = []
        var unreadCount = 0
        var latest: String?
        var questions = 0
        var approvals = 0
        var takeover = false
        var failureID: String?
    }

    private(set) var presentations: [String: Presentation] = [:]
    private var started: [String: Double] = [:]
    private var finished: [String: Double] = [:]
    private var previousRunning: Set<String> = []
    private var failures: [String: String] = [:]
    private var dismissed: [String: String] = [:]
    private var lastHaptic: Double?

    mutating func dismissFailure(sourceID: String) {
        dismissed[sourceID] = failures.removeValue(forKey: sourceID)
    }

    // Priority follows Mode's order; failures and decisions outrank passive updates.
    mutating func reduce(_ snapshots: [Snapshot], now: Double, pointerInside: Bool) -> Bool {
        var next: [String: Presentation] = [:]
        let ids = Set(snapshots.map(\.sourceID))
        started = started.filter { ids.contains($0.key) }
        finished = finished.filter { ids.contains($0.key) }
        failures = failures.filter { ids.contains($0.key) }
        dismissed = dismissed.filter { ids.contains($0.key) }
        var running: Set<String> = []
        for snapshot in snapshots {
            let id = snapshot.sourceID
            if let failure = snapshot.failureID, dismissed[id] != failure { failures[id] = failure }
            if !snapshot.running.isEmpty {
                running.insert(id)
                if started[id] == nil { started[id] = now }
                finished[id] = nil
            } else {
                if previousRunning.contains(id) { finished[id] = now }
                started[id] = nil
            }
            var value = Presentation()
            if !snapshot.running.isEmpty {
                value.mode = .working
                value.agents = Array(snapshot.running.prefix(3))
                value.peek = now >= (started[id] ?? now) + 0.65
            } else if let end = finished[id], now < end + 5.2 {
                value.mode = .working
                value.finished = true
            }
            if snapshot.unreadCount > 0 {
                value = Presentation(mode: .message, unreadCount: snapshot.unreadCount, latest: snapshot.latest)
            }
            if snapshot.takeover { value = Presentation(mode: .takeover) }
            if snapshot.questions > 0 { value = Presentation(mode: .question, remaining: snapshot.questions) }
            if snapshot.approvals > 0 { value = Presentation(mode: .approval, remaining: snapshot.approvals) }
            if failures[id] != nil { value = Presentation(mode: .failed) }
            next[id] = value
        }
        previousRunning = running
        guard !pointerInside else { return false }
        let changed = next != presentations
        presentations = next
        guard changed, lastHaptic.map({ now >= $0 + 0.3 }) ?? true else { return false }
        lastHaptic = now
        return true
    }
}
