import Foundation

@MainActor
protocol TreadmillBluetoothCentral: AnyObject {
    var onEvent: ((TreadmillBluetoothEvent) -> Void)? { get set }
    func start()
    func scan()
    func connect()
    func write(_ data: Data) throws
    func stop()
}

enum TreadmillBluetoothEvent {
    case poweredOn, poweredOff, unauthorized, discovered, ready, disconnected
    case bytes(Data)
    case failed
}

enum TreadmillBluetoothFailure: Error, Equatable {
    case bluetoothOff, unauthorized, padAbsent, connectionFailed
}

@MainActor
final class BluetoothTreadmillTransport: TreadmillTransport {
    var onBytes: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onReady: (() -> Void)?
    var onFailure: (((any Error)?) -> Void)?
    private let central: any TreadmillBluetoothCentral
    private let timeoutDuration: Duration
    private var timeout: Task<Void, Never>?
    private var wanted = false
    private var ready = false
    private var powered = false

    init(central: any TreadmillBluetoothCentral = CoreBluetoothTreadmillCentral(),
         timeout: Duration = .seconds(15)) {
        self.central = central
        timeoutDuration = timeout
        central.onEvent = { [weak self] in self?.receive($0) }
    }

    isolated deinit { timeout?.cancel(); central.stop() }

    func open() throws {
        guard !wanted else { return }
        wanted = true
        central.start()
    }

    func send(_ data: Data) throws {
        guard ready else { throw TreadmillFailure.notReady }
        try central.write(data)
    }

    func close() {
        wanted = false
        ready = false
        powered = false
        timeout?.cancel()
        timeout = nil
        central.stop()
    }

    private func deadline() {
        timeout?.cancel()
        timeout = Task { [weak self, timeoutDuration] in
            do { try await Task.sleep(for: timeoutDuration) } catch { return }
            guard let self, self.wanted, !self.ready else { return }
            self.central.stop()
            self.onFailure?(TreadmillBluetoothFailure.padAbsent)
        }
    }

    private func receive(_ event: TreadmillBluetoothEvent) {
        guard wanted else { return }
        switch event {
        case .poweredOn:
            powered = true
            onFailure?(nil)
            central.scan()
            deadline()
        case .discovered:
            central.connect()
            deadline()
        case .ready:
            timeout?.cancel()
            ready = true
            onFailure?(nil)
            onReady?()
        case .bytes(let data):
            if ready { onBytes?(data) }
        case .disconnected:
            ready = false
            onDisconnect?()
            if wanted, powered { central.connect(); deadline() }
        case .poweredOff, .unauthorized, .failed:
            ready = false
            powered = false
            timeout?.cancel()
            central.stop()
            onDisconnect?()
            let failure: TreadmillBluetoothFailure = switch event {
            case .poweredOff: .bluetoothOff
            case .unauthorized: .unauthorized
            default: .connectionFailed
            }
            onFailure?(failure)
        }
    }
}
