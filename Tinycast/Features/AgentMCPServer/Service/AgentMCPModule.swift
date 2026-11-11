import Foundation

@MainActor
final class AgentMCPModule: NotchcastModule {
    let engine = AgentMCPEngine()

    func start() { engine.start() }
    func stop() { engine.stop() }
}
