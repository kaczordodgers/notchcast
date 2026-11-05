import Foundation

@MainActor
protocol KatanaMIDILayer: AnyObject {
    var endpoints: [String] { get }
    var changed: (() -> Void)? { get set }
    var received: (([UInt8]) -> Void)? { get set }
    func start() throws
    func connect(_ name: String) throws
    func send(_ bytes: [UInt8]) throws
    func stop()
}

@MainActor
final class KatanaMIDITransport: KatanaTransport {
    private(set) var connectionID: UUID?
    private let midi: any KatanaMIDILayer
    private var endpoint: String?
    private var pending: CheckedContinuation<[UInt8], any Error>?
    private var address: Int?
    private var timeout: Task<Void, Never>?
    private var buffer: [UInt8] = []
    private var exchangeID: UUID?

    init(midi: any KatanaMIDILayer) { self.midi = midi }

    func start() {
        midi.changed = { [weak self] in self?.reconnect() }
        do { try midi.start(); reconnect() } catch { disconnect() }
    }

    func stop() {
        disconnect()
        midi.changed = nil
        midi.received = nil
        midi.stop()
    }

    private func disconnect() {
        connectionID = nil
        endpoint = nil
        buffer = []
        finish(.failure(KatanaError.unavailable))
    }

    private func reconnect() {
        let found = midi.endpoints.first { $0.localizedCaseInsensitiveContains("katana") }
        guard found != endpoint else { return }
        disconnect()
        guard let found else { return }
        do {
            try midi.connect(found)
            endpoint = found
            let generation = UUID()
            connectionID = generation
            midi.received = { [weak self] bytes in
                guard self?.connectionID == generation else { return }
                self?.receive(bytes)
            }
        } catch { disconnect() }
    }

    func send(_ packet: [UInt8]) async throws {
        try Task.checkCancellation()
        guard connectionID != nil else { throw KatanaError.unavailable }
        try midi.send(packet)
    }

    func exchange(_ packet: [UInt8]) async throws -> [UInt8] {
        try Task.checkCancellation()
        guard connectionID != nil else { throw KatanaError.unavailable }
        guard pending == nil else { throw KatanaError.busy }
        let message = try KatanaSysEx.decode(packet)
        let id = UUID()
        exchangeID = id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                address = message.address
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    self?.finish(.failure(KatanaError.verificationFailed))
                }
                do { try midi.send(packet) } catch { finish(.failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.exchangeID == id else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func receive(_ bytes: [UInt8]) {
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 { buffer = [byte]; continue }
            guard !buffer.isEmpty else { continue }
            buffer.append(byte)
            if buffer.count > 1024 { buffer = []; continue }
            if byte == 0xF7 {
                let packet = buffer
                buffer = []
                if let message = try? KatanaSysEx.decode(packet),
                   message.command == 0x12, message.address == address {
                    finish(.success(packet))
                }
            }
        }
    }

    private func finish(_ result: Result<[UInt8], any Error>) {
        timeout?.cancel()
        timeout = nil
        let continuation = pending
        pending = nil
        exchangeID = nil
        address = nil
        continuation?.resume(with: result)
    }
}
