import Foundation
import OSLog

@MainActor
final class AgentBridgeModule: NotchcastModule {
    let index = AgentActionIndex()
    private var configured = false
    private var confirmation: AgentConfirmationAuthorization?

    func configure(_ core: AppCore) {
        guard !configured else { return }
        do {
            let grants = try AgentGrantStore(bundleIdentifier: Bundle.main.bundleIdentifier ?? "app.notchcast.dev")
            let audit = AgentAuditStore(directory: AppPaths.applicationSupport().appending(path: "agent"))
            let confirmation = AgentConfirmationAuthorization(grants: grants,
                isEnabled: { NotchcastPreferences.shared.isOn(.agentConfirmation) }) { action, choices in
                await core.choose(title: action.title, message: "local-cli · \(action.id)",
                    symbol: "checkmark.shield", options: choices.map { choice in
                        switch choice {
                        case .allowOnce: DialogAction(title: String(localized: "Allow once"))
                        case .alwaysAllow: DialogAction(title: String(localized: "Always allow"))
                        case .deny: DialogAction(title: String(localized: "Deny"), role: .cancel)
                        }
                    }, defaultIndex: choices.count - 1)
            }
            self.confirmation = confirmation
            index.authorize = { action, parameters in await confirmation.authorize(action, parameters: parameters) }
            index.readAudit = {
                let entries = try await audit.entries()
                return try JSONDecoder().decode(AgentJSON.self, from: JSONEncoder().encode(entries))
            }
            index.didComplete = { request, reply in
                guard request.verb == .run, !request.dryRun else { return }
                let parameters: [String: String]
                if case .object(let fields) = request.parameters {
                    parameters = fields.mapValues { _ in "redacted" }
                } else { parameters = [:] }
                let entry = AgentAuditEntry(time: Date(), agentID: "local-cli", client: "local-cli",
                    surface: .cli, actionID: request.id ?? "", parameters: parameters,
                    verdict: reply.code == .ok ? .ran : reply.code == .declined ? .declined : .failed,
                    succeeded: reply.code == .ok, duration: 0)
                do { try await audit.append(entry) } catch {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentBridge")
                        .error("Unable to append agent audit: \(error)")
                }
            }
            try AgentBuiltInActions.register(in: index, core: core)
            try index.register(.init(id: "notchcast.features", title: String(localized: "Notchcast"), read: {
                .object(Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map {
                    ($0.rawValue, AgentJSON.bool(NotchcastPreferences.shared.isOn($0)))
                }))
            }))
            configured = true
        } catch {
            index.unregisterAll()
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentBridge")
                .error("Unable to register built-in agent actions: \(error)")
        }
    }

    func start() { index.start() }
    func stop() { confirmation?.stop(); index.stop() }
}
