import Foundation
import Observation

@MainActor
final class AgentFleetBotCommands: NotchcastModule {
    private let bots: BotHostModule
    private let preferences: NotchcastPreferences
    private let refresh: () -> Void
    private let post: (String) -> Void
    private var task: Task<Void, Never>?
    private var running = false

    init(bots: BotHostModule, preferences: NotchcastPreferences,
         refresh: @escaping () -> Void, post: @escaping (String) -> Void) {
        self.bots = bots
        self.preferences = preferences
        self.refresh = refresh
        self.post = post
    }

    func start() {
        running = true
        AgentFleetCommands.run = { [weak self] in self?.perform($0) }
        observe()
    }

    func stop() {
        running = false
        task?.cancel()
        AgentFleetCommands.enabled = false
        AgentFleetCommands.run = { _ in }
        refresh()
    }

    private func observe() {
        guard running else { return }
        withObservationTracking {
            AgentFleetCommands.enabled = preferences.isOn(.botHost)
            if !AgentFleetCommands.enabled { task?.cancel() }
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func perform(_ operation: String) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                guard bots.isConfigured else {
                    post(String(localized: "Bot host unavailable"))
                    return
                }
                let list = try await bots.list()
                var lines: [String] = []
                for bot in list {
                    switch operation {
                    case "bot-status": lines.append("\(bot.name): \(try await bots.status(botID: bot.id))")
                    case "bot-pending": lines.append("\(bot.name): \(try await bots.pending(botID: bot.id).count)")
                    default: lines.append(bot.name)
                    }
                }
                guard !Task.isCancelled, preferences.isOn(.botHost) else { return }
                post(lines.isEmpty ? String(localized: "No bots available") : lines.joined(separator: "\n"))
            } catch {
                guard !Task.isCancelled, preferences.isOn(.botHost) else { return }
                post(error.localizedDescription)
            }
        }
    }
}
