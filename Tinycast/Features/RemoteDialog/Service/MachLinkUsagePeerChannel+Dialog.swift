import Foundation
import Network

extension MachLinkUsagePeerChannel {
    func sendDialogNotice(_ notice: RemoteDialogModule.Notice) async throws {
        guard let pairing else { throw MachLinkMessage.Failure.disconnected }
        let remotes = manager.peers.filter {
            guard case let .service(name, _, _, _) = $0.endpoint,
                  name != manager.serviceName, case let .bonjour(record) = $0.metadata else { return false }
            return record["pairing"] == pairing.discoveryHash
        }
        let endpoints = endpoint.map { [$0] } ?? remotes.map(\.endpoint)
        for endpoint in endpoints.prefix(2) {
            try Task.checkCancellation()
            do {
                let accepted = try await MachLinkManager.request(
                    notice, method: "dialog-shown", from: endpoint, pairing: pairing,
                    timeout: .seconds(2), as: Bool.self)
                if accepted { return }
            } catch is CancellationError { throw CancellationError() } catch { continue }
        }
        throw MachLinkMessage.Failure.disconnected
    }
}
