import Foundation

@MainActor
final class AgentMCPModule: NotchcastModule {
    let engine: AgentMCPEngine

    init(backend: any AgentMCPBackend = AgentMCPUnavailableBackend()) {
        engine = AgentMCPEngine(backend: backend)
    }

    func start() { engine.start() }
    func stop() { engine.stop() }
}

@MainActor
struct AgentMCPUnavailableBackend: AgentMCPBackend {
    func actions() async throws -> [AgentMCPAction] { [] }
    func states() async throws -> [AgentMCPState] { [] }
    func call(_ id: String, arguments: Data) async throws -> Data { throw CancellationError() }
    func readState(_ id: String) async throws -> Data { throw CancellationError() }
}
