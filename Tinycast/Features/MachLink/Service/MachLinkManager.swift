import Foundation
import Network
import Observation

@MainActor
@Observable
final class MachLinkManager {
    static let serviceType = "_notchcast-link._tcp"
    typealias Route = @MainActor (MachLinkMessage) async throws -> MachLinkMessage

    private(set) var listener: NWListener?
    private(set) var browser: NWBrowser?
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var routes: [String: Route] = [:]
    private(set) var peers: Set<NWBrowser.Result> = []
    var port: NWEndpoint.Port? { listener?.port }
    private(set) var serviceName: String?
    private var pairing: MachLinkPairing?
    private var restart: Task<Void, Never>?

    isolated deinit {
        listener?.cancel()
        browser?.cancel()
        for task in requests.values { task.cancel() }
    }

    func start(pairing: MachLinkPairing, name: String) throws {
        stop()
        let listener = try NWListener(using: MachLinkTransport.parameters(pairing: pairing))
        self.listener = listener
        self.pairing = pairing
        serviceName = name
        listener.stateUpdateHandler = { @Sendable [weak self, weak listener] state in
            guard case .failed = state else { return }
            Task { @MainActor [weak self, weak listener] in
                guard let listener, self?.listener === listener else { return }
                self?.restartAfterFailure()
            }
        }
        listener.service = NWListener.Service(name: name, type: Self.serviceType,
            txtRecord: NWTXTRecord(["pairing": pairing.discoveryHash]))
        listener.newConnectionHandler = { @Sendable [weak self, weak listener] connection in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener, self.requests.count < 8 else {
                    connection.cancel()
                    return
                }
                let id = UUID()
                self.requests[id] = Task { [weak self] in
                    defer { self?.requests[id] = nil }
                    do {
                        guard let manager = self else { throw MachLinkMessage.Failure.disconnected }
                        try await MachLinkTransport.bounded(connection: connection, timeout: MachLinkRequestBudget.responder) {
                            try await MachLinkTransport.bounded(
                                connection: connection, timeout: .seconds(1), cancelOnSuccess: false
                            ) {
                                try await MachLinkTransport.connected(connection)
                            }
                            let request = try await MachLinkTransport.receive(on: connection)
                            let response = try await manager.response(to: request)
                            guard response.id == request.id, response.method == request.method else {
                                throw MachLinkMessage.Failure.invalidMessage
                            }
                            try await MachLinkTransport.send(response, on: connection)
                        }
                    } catch { connection.cancel() }
                }
            }
        }
        listener.start(queue: .main)
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { @Sendable [weak self, weak browser] state in
            guard case .failed = state else { return }
            Task { @MainActor [weak self, weak browser] in
                guard let browser, self?.browser === browser else { return }
                self?.restartAfterFailure()
            }
        }
        browser.browseResultsChangedHandler = { @Sendable [weak self, weak browser] results, _ in
            Task { @MainActor [weak self, weak browser] in
                guard let browser, self?.browser === browser else { return }
                self?.peers = results
            }
        }
        browser.start(queue: .main)
    }

    /// A failed listener or browser is terminal; restart after a delay so failures never spin.
    private func restartAfterFailure() {
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, let pairing, let name = serviceName else { return }
            do { try start(pairing: pairing, name: name) } catch { restartAfterFailure() }
        }
    }

    func stop() {
        restart?.cancel()
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        peers = []
        for task in requests.values { task.cancel() }
        requests.removeAll()
    }

    func register(_ method: String, _ route: @escaping Route) {
        routes[method] = route
    }

    private func response(to request: MachLinkMessage) async throws -> MachLinkMessage {
        guard let route = routes[request.method] else { throw MachLinkMessage.Failure.invalidMessage }
        return try await route(request)
    }

    nonisolated static func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ value: Request, method: String, from endpoint: NWEndpoint,
        pairing: MachLinkPairing, timeout: Duration = MachLinkRequestBudget.requester, as type: Response.Type
    ) async throws -> Response {
        let message = try MachLinkMessage(method: method, value: value)
        let connection = NWConnection(to: endpoint, using: MachLinkTransport.parameters(pairing: pairing))
        return try await MachLinkTransport.bounded(connection: connection, timeout: timeout) {
            try await MachLinkTransport.connected(connection)
            try await MachLinkTransport.send(message, on: connection)
            let response = try await MachLinkTransport.receive(on: connection)
            guard response.id == message.id, response.method == method else {
                throw MachLinkMessage.Failure.invalidMessage
            }
            return try response.value(as: type)
        }
    }
}
