import Foundation
import Network

extension BlockedDialogModule {
    static func linked(to channel: MachLinkUsagePeerChannel) -> BlockedDialogModule {
        BlockedDialogModule(transport: { request in
            guard let pairing = channel.pairing else { throw MachLinkMessage.Failure.disconnected }
            let endpoints = channel.endpoint.map { [$0] } ?? channel.manager.peers.filter {
                guard case let .service(name, _, _, _) = $0.endpoint,
                      name != channel.manager.serviceName,
                      case let .bonjour(record) = $0.metadata else { return false }
                return record["pairing"] == pairing.discoveryHash
            }.map(\.endpoint)
            guard let endpoint = endpoints.first else { throw MachLinkMessage.Failure.disconnected }
            let windows = try await MachLinkManager.request(true, method: request.method,
                from: endpoint, pairing: pairing, timeout: .seconds(2), as: [BlockedDialogWindow].self)
            return try MachLinkMessage(id: request.id, method: request.method, value: windows)
        }, enabled: {
            [.machLink, .island, .islandStatusMessages, .machBlockedDialogAlert]
                .allSatisfy { NotchcastPreferences.shared.isOn($0) }
        }, present: { owner in
            IslandActivityCenter.shared.showMessage(
                String(localized: "Other Mac: \(owner) is waiting.", table: "Notchcast"), tone: .neutral, dwell: 8)
        })
    }
}
