import Foundation
import OSLog

@MainActor
final class AgentBridgeModule: NotchcastModule {
    let index = AgentActionIndex()
    private var configured = false

    func configure(_ core: AppCore) {
        guard !configured else { return }
        do {
            try AgentBuiltInActions.register(in: index, core: core)
            try index.register(.init(id: "notchcast.features", title: String(localized: "Notchcast"), read: {
                .object(Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map {
                    ($0.rawValue, AgentJSON.bool(NotchcastPreferences.shared.isOn($0)))
                }))
            }))
            configured = true
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentBridge")
                .error("Unable to register built-in agent actions: \(error)")
        }
    }

    func start() { index.start() }
    func stop() { index.stop() }
}
