import Foundation
import Observation

@MainActor
@Observable
final class AgentIslandModule: NotchcastModule {
    private(set) var presentation = AgentIslandEngine.Presentation()
    @ObservationIgnored private var engine = AgentIslandEngine()
    private let threads: AgentThreadsModule
    private let bots: OpenBotAgentsModule
    private let enabled: (AgentIslandEngine.Source) -> Bool
    private let now: () -> Date
    private let availabilityChanged: () -> Void
    private var running = false
    private var visible = false
    private var refreshing = false
    private var t3Active = false
    private var botActive = false
    private var refreshIdentity = UUID()
    private var threadsReady = false
    private var botsReady = false
    private var refreshCompletion: (@MainActor (AgentIslandEngine.Message) -> Void)?
    private var generation = UUID()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(threads: AgentThreadsModule, bots: OpenBotAgentsModule,
         enabled: @escaping (AgentIslandEngine.Source) -> Bool,
         now: @escaping () -> Date = { Date() }, availabilityChanged: @escaping () -> Void) {
        self.threads = threads
        self.bots = bots
        self.enabled = enabled
        self.now = now
        self.availabilityChanged = availabilityChanged
    }

    func start() {
        guard !running else { return }
        running = true
        generation = UUID()
        observe(generation)
        availabilityChanged()
    }

    func stop() {
        running = false
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        if visible { setVisible(false) }
        refreshing = false
        refreshIdentity = UUID()
        refreshCompletion = nil
        engine = AgentIslandEngine()
        presentation = engine.presentation
        availabilityChanged()
    }

    func setVisible(_ value: Bool) {
        visible = value && running
        applyVisibility()
    }

    private func applyVisibility() {
        let nextT3 = visible && enabled(.t3)
        let nextBot = visible && !refreshing && enabled(.openBot)
        if nextT3 != t3Active {
            t3Active = nextT3
            threads.setActive(nextT3)
        }
        if nextBot != botActive {
            botActive = nextBot
            bots.setActive(nextBot)
        }
    }

    func update() {
        guard running else { return }
        engine.update(threads: threads.state.threads, pending: bots.pending,
                      t3Enabled: enabled(.t3), openBotEnabled: enabled(.openBot), now: now())
        if presentation != engine.presentation { presentation = engine.presentation }
    }

    func dismissFailed(_ thread: AgentThread) {
        engine.dismissFailed(thread)
        update()
    }

    func openItem(source: AgentIslandEngine.Source, thread: AgentThread?) -> URL? {
        source == .t3 ? thread?.link : nil
    }

    func refresh(completion: @escaping @MainActor (AgentIslandEngine.Message) -> Void) {
        guard running else { return }
        refreshTask?.cancel()
        refreshIdentity = UUID()
        let identity = refreshIdentity
        refreshCompletion = completion
        threadsReady = !enabled(.t3)
        botsReady = !enabled(.openBot)
        let refreshBots = !botsReady
        refreshing = true
        applyVisibility()
        if !threadsReady {
            if threads.state.status != .loading {
                threads.state.refresh { [weak self] _ in self?.threadsFinished(identity) }
            }
            observeThreadsRefresh(identity)
        }
        refreshTask = Task { [weak self, bots] in
            if refreshBots { await bots.waitUntilIdle() }
            guard let self, !Task.isCancelled, self.running, self.refreshIdentity == identity else { return }
            if !self.botsReady {
                bots.refresh()
                await bots.waitUntilIdle()
            }
            guard !Task.isCancelled, self.running, self.refreshIdentity == identity else { return }
            self.botsReady = true
            self.finishRefresh()
        }
    }

    private func observeThreadsRefresh(_ identity: UUID) {
        guard running, refreshIdentity == identity else { return }
        let loading = withObservationTracking {
            threads.state.status == .loading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeThreadsRefresh(identity) }
        }
        if !loading { threadsFinished(identity) }
    }

    private func threadsFinished(_ identity: UUID) {
        guard running, refreshIdentity == identity else { return }
        threadsReady = true
        finishRefresh()
    }

    private func finishRefresh() {
        guard threadsReady, botsReady, let completion = refreshCompletion else { return }
        refreshCompletion = nil
        update()
        refreshing = false
        refreshTask = nil
        applyVisibility()
        completion(presentation.message)
    }

    private func observe(_ identity: UUID) {
        guard running, generation == identity else { return }
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe(identity) }
        }
    }

    nonisolated static let command = NotchcastCommand(slug: "show-agent-status",
        name: String(localized: "Show Agent Status"), sfSymbol: "bubble.left", feature: .agentIsland,
        isEnabled: { NotchcastPreferences.shared.isOn(.agentIsland) },
        run: { NotchcastCore.agentIsland.refresh { message in
            let text: String
            switch message {
            case .idle: text = String(localized: "No agents active.")
            case let .counts(waiting, working): text = String(localized: "\(waiting) waiting, \(working) working.")
            }
            AppCore.shared.showMessage(text, tone: .neutral)
        } })
}
