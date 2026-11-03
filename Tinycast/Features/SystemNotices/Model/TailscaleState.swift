import Foundation

enum TailscaleState: String, Sendable, Equatable {
    case connected, disconnected, starting, needsLogin, needsApproval, unavailable

    static func parse(_ data: Data) -> Self {
        struct Status: Decodable {
            let backendState: String
            enum CodingKeys: String, CodingKey { case backendState = "BackendState" }
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { return .unavailable }
        return switch status.backendState {
        case "Running": .connected
        case "Stopped": .disconnected
        case "Starting": .starting
        case "NeedsLogin": .needsLogin
        case "NeedsMachineAuth": .needsApproval
        default: .unavailable
        }
    }
}
