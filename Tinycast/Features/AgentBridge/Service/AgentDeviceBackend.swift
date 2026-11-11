import Foundation

@MainActor
protocol AgentDeviceBackend: AnyObject {
    var deviceName: String { get }
    var operations: [(name: String, parameters: AgentParameterSchema)] { get }
    var isAvailable: Bool { get }
    func readState() async throws -> AgentJSON
    func perform(_ operation: String, parameters: AgentJSON) async throws -> AgentJSON
}
