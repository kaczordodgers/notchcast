import Foundation
import OSLog

@MainActor
final class AgentBridgeModule: NotchcastModule {
    let index = AgentActionIndex()
    private(set) var configured = false
    private var confirmation: AgentConfirmationAuthorization?

    func configure(_ core: AppCore) {
        guard !configured else { return }
        do {
            let grants = try AgentGrantStore(bundleIdentifier: NotchcastIdentity.current.bundleID)
            let audit = AgentAuditStore(directory: NotchcastIdentity.supportRoot.appending(path: "agent"))
            let confirmation = AgentConfirmationAuthorization(grants: grants,
                isEnabled: { NotchcastPreferences.shared.isOn(.agentConfirmation) },
                timeout: AgentRequestTiming.confirmationTimeout) { action, message, choices in
                await withTaskCancellationHandler {
                    await core.choose(title: action.title, message: message,
                        symbol: "checkmark.shield", options: choices.map { choice in
                            switch choice {
                            case .allowOnce: DialogAction(title: String(localized: "Allow once", table: "Notchcast"))
                            case .alwaysAllow: DialogAction(title: String(localized: "Always allow", table: "Notchcast"))
                            case .deny: DialogAction(title: String(localized: "Deny", table: "Notchcast"), role: .cancel)
                            }
                        }, defaultIndex: choices.count - 1)
                } onCancel: {
                    Task { @MainActor in DialogPanel.dismissOpen() }
                }
            }
            self.confirmation = confirmation
            // MCP shares the local CLI agent identity and its consent grants.
            index.authorize = { action, parameters in await confirmation.authorize(action, parameters: parameters) }
            index.readAudit = {
                let entries = try await audit.entries()
                return try JSONDecoder().decode(AgentJSON.self, from: JSONEncoder().encode(entries))
            }
            index.didComplete = { request, reply in
                guard let entry = request.auditEntry(reply: reply, time: Date()) else { return }
                do { try await audit.append(entry) } catch {
                    Logger(subsystem: NotchcastIdentity.current.bundleID, category: "AgentBridge")
                        .error("Unable to append agent audit: \(error)")
                }
            }
            try AgentBuiltInActions.register(in: index, core: core)
            for device in NotchcastAgentDevice.all { device.configure(index) }
            try index.register(.init(id: "notchcast.features", title: String(localized: "Notchcast", table: "Notchcast"), read: {
                .object(Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map {
                    ($0.rawValue, AgentJSON.bool(NotchcastPreferences.shared.isOn($0)))
                }))
            }))
            configured = true
        } catch {
            index.unregisterAll()
            Logger(subsystem: NotchcastIdentity.current.bundleID, category: "AgentBridge")
                .error("Unable to register built-in agent actions: \(error)")
        }
    }

    func start() { index.start() }
    func stop() { confirmation?.stop(); index.stop() }
}
