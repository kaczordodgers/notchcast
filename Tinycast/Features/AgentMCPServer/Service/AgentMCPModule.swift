import Foundation

@MainActor
final class AgentMCPModule: NotchcastModule {
    let engine: AgentMCPEngine

    init(backend: (any AgentMCPBackend)? = nil) {
        engine = AgentMCPEngine(backend: backend)
    }

    func start() { engine.start() }
    func stop() { engine.stop() }
}
