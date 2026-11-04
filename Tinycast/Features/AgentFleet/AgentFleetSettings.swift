import Foundation
import Observation

@MainActor @Observable
final class AgentFleetSettings {
    private let defaults: UserDefaults
    let tokenAccount: UUID
    var remoteEnvironmentID: String { didSet { defaults.set(remoteEnvironmentID, forKey: "fleetRemoteID") } }
    var botURL: String { didSet { defaults.set(botURL, forKey: "botHostURL") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        remoteEnvironmentID = defaults.string(forKey: "fleetRemoteID") ?? ""
        botURL = defaults.string(forKey: "botHostURL") ?? ""
        tokenAccount = defaults.string(forKey: "botHostAccount").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(tokenAccount.uuidString, forKey: "botHostAccount")
    }

    var destinations: [FleetSnapshot.Destination] {
        var result: [FleetSnapshot.Destination] = [
            .init(machine: "", environmentID: "", workspacePath: nil, route: .local)
        ]
        if !remoteEnvironmentID.isEmpty {
            result.append(.init(machine: "", environmentID: remoteEnvironmentID, workspacePath: nil, route: .linked))
        }
        return result
    }
}
