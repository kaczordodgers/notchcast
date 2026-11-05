import Foundation
import Observation

@MainActor
@Observable
final class AgentIslandModule: NotchcastModule {
    private(set) var presentation = AgentIslandEngine.Presentation()
    private var engine = AgentIslandEngine()
    private let threads: AgentThreadsModule
    private let bots: OpenBotAgentsModule
    private let enabled: (AgentIslandEngine.Source) -> Bool
    private let now: () -> Date
    private let availabilityChanged: () -> Void
    private var running = false
    private var visible = false
    private var refreshing = false
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
        refreshing = false
        setVisible(false)
        engine = AgentIslandEngine()
        presentation = engine.presentation
        availabilityChanged()
    }

    func setVisible(_ value: Bool) {
        visible = value && running
        applyVisibility()
    }

    private func applyVisibility() {
        threads.setActive(visible && !refreshing && enabled(.t3))
        bots.setActive(visible && !refreshing && enabled(.openBot))
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
        let identity = generation
        refreshing = true
        applyVisibility()
        if enabled(.t3) { threads.state.refresh() }
        if enabled(.openBot) { bots.refresh() }
        refreshTask = Task { [weak self, threads, bots] in
            await threads.state.waitUntilIdle()
            await bots.waitUntilIdle()
            guard let self, !Task.isCancelled, self.running, self.generation == identity else { return }
            self.update()
            completion(self.presentation.message)
            self.refreshing = false
            self.refreshTask = nil
            self.applyVisibility()
        }
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
