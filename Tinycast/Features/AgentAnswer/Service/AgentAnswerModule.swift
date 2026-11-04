import Foundation

@MainActor
final class AgentAnswerModule: NotchcastModule {
    private(set) var isRunning = false
    private var pending: Set<[String]> = []
    private var accepted: Set<[String]> = []
    private var generation = 0

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        generation += 1
    }

    func answer(_ answer: AgentAnswer, item: AgentAnswerItem,
                transport: any AgentAnswerTransport) async -> AgentAnswerResult {
        guard isRunning else { return .disabled }
        guard valid(answer, for: item) else { return .invalidAnswer }
        let key = [String(describing: item.source), item.id, item.revision]
        guard !accepted.contains(key) else { return .alreadyAnswered }
        guard pending.insert(key).inserted else { return .inProgress }
        defer { pending.remove(key) }
        let operation = generation
        do {
            try Task.checkCancellation()
            let result = try await transport.send(answer, to: item)
            if result == .sent || result == .queued || result == .alreadyAnswered {
                accepted.insert(key)
            }
            guard !Task.isCancelled, operation == generation, isRunning else { return .cancelled }
            return result
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func valid(_ answer: AgentAnswer, for item: AgentAnswerItem) -> Bool {
        switch answer {
        case let .reply(text): !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .choice(choice): item.source != .t3 && item.choices.contains(choice)
        case .approve: item.source != .t3 && item.allowsApprove
        case .deny: item.source != .t3 && item.allowsDeny
        }
    }
}
