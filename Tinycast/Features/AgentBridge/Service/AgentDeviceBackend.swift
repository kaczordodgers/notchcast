import Foundation

@MainActor
protocol AgentDeviceBackend: AnyObject {
    var isAvailable: Bool { get }
    func readState() async throws -> AgentJSON
    func perform(_ operation: String, parameters: AgentJSON) async throws -> AgentJSON
}
