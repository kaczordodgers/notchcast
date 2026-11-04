import Foundation
import Network
import Security
import Synchronization

enum MachLinkTransport {
    static func parameters(pairing: MachLinkPairing) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: 0x00A8)!)
        let key = pairing.secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(pairing.id.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as dispatch_data_t, identity as dispatch_data_t)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }

    static func connected(_ connection: NWConnection) async throws {
        let completion = Mutex<(CheckedContinuation<Void, Error>?, Result<Void, Error>?)>((nil, nil))
        @Sendable func finish(_ result: Result<Void, Error>) {
            let continuation = completion.withLock { state -> CheckedContinuation<Void, Error>? in
                guard state.1 == nil else { return nil }
                state.1 = result
                defer { state.0 = nil }
                return state.0
            }
            continuation?.resume(with: result)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let result = completion.withLock { state -> Result<Void, Error>? in
                    if let result = state.1 { return result }
                    state.0 = continuation
                    return nil
                }
                if let result {
                    continuation.resume(with: result)
                    return
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.stateUpdateHandler = nil
                        finish(.success(()))
                    case let .failed(error):
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                        finish(.failure(error))
                    case .cancelled:
                        connection.stateUpdateHandler = nil
                        finish(.failure(CancellationError()))
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }
        } onCancel: {
            finish(.failure(CancellationError()))
            connection.cancel()
        }
    }

    static func send(_ message: MachLinkMessage, on connection: NWConnection) async throws {
        let body = try message.encoded()
        var length = UInt32(body.count).bigEndian
        let frame = withUnsafeBytes(of: &length) { Data($0) } + body
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    static func receive(on connection: NWConnection) async throws -> MachLinkMessage {
        let header = try await read(4, on: connection)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= MachLinkMessage.maximumBytes else {
            throw MachLinkMessage.Failure.tooLarge
        }
        return try MachLinkMessage.decode(await read(length, on: connection))
    }

    private static func read(_ count: Int, on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: MachLinkMessage.Failure.disconnected)
                }
            }
        }
    }

    static func bounded<Value: Sendable>(
        connection: NWConnection, timeout: Duration, cancelOnSuccess: Bool = true,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await withTaskCancellationHandler(operation: operation, onCancel: { connection.cancel() })
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw MachLinkMessage.Failure.timedOut
            }
            defer { group.cancelAll(); if cancelOnSuccess { connection.cancel() } }
            return try await group.next()!
        }
    }
}
