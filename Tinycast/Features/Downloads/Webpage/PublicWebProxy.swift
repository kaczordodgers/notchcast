import Foundation
import Network

@MainActor
final class PublicWebProxy {
    private let listener: NWListener
    private let username = UUID().uuidString
    private let password = UUID().uuidString + UUID().uuidString
    private var tunnels: [UUID: Tunnel] = [:]
    private var remainingBytes = 200 * 1_024 * 1_024
    private var startContinuation: CheckedContinuation<ProxyConfiguration, any Error>?
    private var stopped = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> ProxyConfiguration {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        listener.cancel()
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        let active = Array(tunnels.values)
        tunnels.removeAll()
        for tunnel in active { tunnel.close() }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port, !stopped else { return }
            var configuration = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
            configuration.allowFailover = false
            configuration.matchDomains = [""]
            configuration.excludedDomains = []
            configuration.applyCredential(username: username, password: password)
            startContinuation?.resume(returning: configuration)
            startContinuation = nil
        case .failed(let error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            stop()
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, tunnels.count < 32, remainingBytes > 0 else { connection.cancel(); return }
        let id = UUID()
        let tunnel = Tunnel(connection: connection, username: username, password: password,
                            consume: { [weak self] count in
            guard let self, !self.stopped, count <= self.remainingBytes else { return false }
            self.remainingBytes -= count
            return true
        }, finished: { [weak self] in self?.tunnels[id] = nil })
        tunnels[id] = tunnel
        tunnel.start()
    }

    @MainActor
    private final class Tunnel {
        private let client: NWConnection
        private var upstream: NWConnection?
        private let username: String
        private let password: String
        private let consume: (Int) -> Bool
        private let finished: () -> Void
        private var work: Task<Void, Never>?
        private var deadline: Task<Void, Never>?
        private var connectContinuation: CheckedContinuation<Void, any Error>?
        private var closed = false

        init(connection: NWConnection, username: String, password: String,
             consume: @escaping (Int) -> Bool, finished: @escaping () -> Void) {
            client = connection
            self.username = username
            self.password = password
            self.consume = consume
            self.finished = finished
        }

        func start() {
            client.start(queue: .main)
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.close()
            }
            work = Task { [weak self] in await self?.handshake() }
        }

        func close() {
            guard !closed else { return }
            closed = true
            work?.cancel()
            deadline?.cancel()
            upstream?.stateUpdateHandler = nil
            connectContinuation?.resume(throwing: CancellationError())
            connectContinuation = nil
            client.cancel()
            upstream?.cancel()
            finished()
        }

        private func read(_ count: Int) async throws -> [UInt8] {
            guard !closed, count > 0 else { throw CancellationError() }
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                client.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, complete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, data.count == count {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: URLError(complete ? .networkConnectionLost : .badServerResponse))
                    }
                }
            }
            try Task.checkCancellation()
            return Array(data)
        }

        private func send(_ bytes: [UInt8], to connection: NWConnection) async throws {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                connection.send(content: Data(bytes), completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        }

        private func handshake() async {
            do {
                let greeting = try await read(2)
                guard greeting[0] == 5, greeting[1] > 0 else { throw URLError(.badServerResponse) }
                let methods = try await read(Int(greeting[1]))
                guard methods.contains(2) else { throw URLError(.userAuthenticationRequired) }
                try await send([5, 2], to: client)
                let auth = try await read(2)
                guard auth[0] == 1, auth[1] > 0 else { throw URLError(.userAuthenticationRequired) }
                let user = try await read(Int(auth[1]))
                let length = try await read(1)
                let secret = try await read(Int(length[0]))
                guard user == Array(username.utf8), secret == Array(password.utf8) else {
                    throw URLError(.userAuthenticationRequired)
                }
                try await send([1, 0], to: client)
                let request = try await read(4)
                guard request[0] == 5, request[1] == 1, request[2] == 0 else { throw URLError(.unsupportedURL) }
                let host = try await destination(request[3])
                let portBytes = try await read(2)
                let port = UInt16(portBytes[0]) * 256 + UInt16(portBytes[1])
                let addresses = try await PublicWebAddress.resolve(host, port: port)
                try Task.checkCancellation()
                guard !closed, let endpointPort = NWEndpoint.Port(rawValue: port) else {
                    throw CancellationError()
                }
                let connection = try await connect(addresses, port: endpointPort)
                try await send([5, 0, 0, 1, 0, 0, 0, 0, 0, 0], to: client)
                relay(from: client, to: connection)
                relay(from: connection, to: client)
            } catch { close() }
        }

        private func destination(_ type: UInt8) async throws -> String {
            switch type {
            case 1:
                return try await read(4).map(String.init).joined(separator: ".")
            case 3:
                let length = try await read(1)
                let bytes = try await read(Int(length[0]))
                guard let host = String(bytes: bytes, encoding: .utf8) else { throw URLError(.badURL) }
                return host
            case 4:
                let bytes = try await read(16)
                return stride(from: 0, to: 16, by: 2).map {
                    String(UInt16(bytes[$0]) * 256 + UInt16(bytes[$0 + 1]), radix: 16)
                }.joined(separator: ":")
            default: throw URLError(.unsupportedURL)
            }
        }

        private func connect(_ addresses: [String], port: NWEndpoint.Port) async throws -> NWConnection {
            var lastError: any Error = URLError(.cannotConnectToHost)
            for address in addresses {
                try Task.checkCancellation()
                guard !closed else { throw CancellationError() }
                let parameters = NWParameters.tcp
                parameters.preferNoProxies = true
                let connection = NWConnection(host: NWEndpoint.Host(address), port: port, using: parameters)
                upstream = connection
                do {
                    try await connect(connection)
                    try Task.checkCancellation()
                    guard !closed else { throw CancellationError() }
                    return connection
                } catch {
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    try Task.checkCancellation()
                    guard !closed else { throw CancellationError() }
                    lastError = error
                }
            }
            throw lastError
        }

        private func connect(_ connection: NWConnection) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                connectContinuation = continuation
                connection.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.upstream === connection,
                              let pending = self.connectContinuation else { return }
                        switch state {
                        case .ready:
                            connection.stateUpdateHandler = nil
                            self.connectContinuation = nil
                            pending.resume()
                        case .failed(let error), .waiting(let error):
                            connection.stateUpdateHandler = nil
                            self.connectContinuation = nil
                            pending.resume(throwing: error)
                        case .cancelled:
                            connection.stateUpdateHandler = nil
                            self.connectContinuation = nil
                            pending.resume(throwing: CancellationError())
                        default: break
                        }
                    }
                }
                connection.start(queue: .main)
            }
        }

        private func relay(from source: NWConnection, to destination: NWConnection) {
            guard !closed else { return }
            source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
                Task { @MainActor in
                    guard let self, !self.closed else { return }
                    guard let data, !data.isEmpty, self.consume(data.count) else { self.close(); return }
                    destination.send(content: data, completion: .contentProcessed { [weak self] sendError in
                        Task { @MainActor in
                            guard let self else { return }
                            if complete || error != nil || sendError != nil {
                                self.close()
                            } else {
                                self.relay(from: source, to: destination)
                            }
                        }
                    })
                }
            }
        }
    }
}
