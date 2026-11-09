import Foundation
import Network

@MainActor
final class MachLinkManager {
    static let serviceType = "_notchcast-link._tcp"
    typealias Handler = @Sendable (MachLinkMessage) async throws -> MachLinkMessage
    typealias Route = @MainActor (MachLinkMessage) async throws -> MachLinkMessage

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var routes: [String: Route] = [:]
    private(set) var peers: Set<NWBrowser.Result> = []
    var port: NWEndpoint.Port? { listener?.port }
    private(set) var serviceName: String?
    var fanHandler: (@MainActor (RemoteFanRequest) async throws -> RemoteFanReport)?
    var fanEnabled: @MainActor () -> Bool = {
        [.machLink, .systemMonitor, .fanControl].allSatisfy { NotchcastPreferences.shared.isOn($0) }
    }

    isolated deinit {
        listener?.cancel()
        browser?.cancel()
        for task in requests.values { task.cancel() }
    }

    func start(pairing: MachLinkPairing, name: String, handler: @escaping Handler) throws {
        stop()
        let listener = try NWListener(using: MachLinkTransport.parameters(pairing: pairing))
        self.listener = listener
        serviceName = name
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
                            let response = try await manager.response(to: request, fallback: handler)
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
        browser.browseResultsChangedHandler = { @Sendable [weak self, weak browser] results, _ in
            Task { @MainActor [weak self, weak browser] in
                guard let browser, self?.browser === browser else { return }
                self?.peers = results
            }
        }
        browser.start(queue: .main)
    }

    func stop() {
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

    private func response(to request: MachLinkMessage, fallback: Handler) async throws -> MachLinkMessage {
        if let reply = try await peerResponse(to: request) { return reply }
        guard let route = routes[request.method] else { return try await fallback(request) }
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
