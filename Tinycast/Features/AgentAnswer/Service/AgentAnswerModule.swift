import Foundation

@MainActor
final class AgentAnswerModule: NotchcastModule {
    private(set) var isRunning = false
    private var pending: Set<[String]> = []
    private var accepted: Set<[String]> = []
    private var generation = 0
    private(set) var items: [AgentAnswerItem] = []
    private(set) var pollingFailure: String?
    private var source: (any AgentAnswerPendingSource)?
    private var pollingTask: Task<Void, Never>?
    private let pollInterval: Duration

    init(pollInterval: Duration = .seconds(5)) {
        self.pollInterval = pollInterval
    }

    func configure(source: (any AgentAnswerPendingSource)?) {
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        items = []
        pollingFailure = nil
        self.source = source
        if isRunning { beginPolling() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        beginPolling()
    }

    func stop() {
        isRunning = false
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        items = []
        pollingFailure = nil
    }

    private func beginPolling() {
        guard let source else { return }
        let operation = generation
        let interval = pollInterval
        pollingTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    let fetched = try await source.pendingItems()
                    guard let self, !Task.isCancelled, isRunning, generation == operation else { return }
                    items = fetched
                    pollingFailure = nil
                    failures = 0
                } catch {
                    guard let self, !Task.isCancelled, isRunning, generation == operation else { return }
                    pollingFailure = error.localizedDescription
                    failures = min(failures + 1, 6)
                }
                do {
                    try await Task.sleep(for: interval * (1 << failures))
                } catch { return }
            }
        }
    }

    isolated deinit { pollingTask?.cancel() }

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
