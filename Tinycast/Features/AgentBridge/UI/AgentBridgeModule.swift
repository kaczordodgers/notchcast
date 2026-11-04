import Foundation
import OSLog

@MainActor
final class AgentBridgeModule: NotchcastModule {
    let index = AgentActionIndex()
    private var configured = false

    func configure(_ core: AppCore) {
        guard !configured else { return }
        do {
            let grants = try AgentGrantStore(bundleIdentifier: Bundle.main.bundleIdentifier ?? "app.notchcast.dev")
            let audit = AgentAuditStore(directory: AppPaths.applicationSupport().appending(path: "agent"))
            index.authorize = { action, _ in
                let danger: AgentConsentPolicy.Danger = switch action.danger {
                case .harmless: .safe
                case .consent: .consent
                case .dangerous: .dangerous
                }
                // MCP shares the local CLI agent identity and its consent grants.
                return AgentConsentPolicy.decide(agentID: "local-cli", actionID: action.id,
                    danger: danger, grants: grants.grants, now: Date()) == .allow
            }
            index.readAudit = {
                let entries = try await audit.entries()
                return try JSONDecoder().decode(AgentJSON.self, from: JSONEncoder().encode(entries))
            }
            index.didComplete = { request, reply in
                guard let entry = request.auditEntry(reply: reply, time: Date()) else { return }
                do { try await audit.append(entry) } catch {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentBridge")
                        .error("Unable to append agent audit: \(error)")
                }
            }
            try AgentBuiltInActions.register(in: index, core: core)
            NotchcastCore.katana.configure(index: index)
            try index.register(.init(id: "notchcast.features", title: String(localized: "Notchcast"), read: {
                .object(Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map {
                    ($0.rawValue, AgentJSON.bool(NotchcastPreferences.shared.isOn($0)))
                }))
            }))
            configured = true
            NotchcastCore.agentMCPServer.configure(index: index)
        } catch {
            index.unregisterAll()
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentBridge")
                .error("Unable to register built-in agent actions: \(error)")
        }
    }

    func start() { index.start() }
    func stop() { index.stop() }
}
