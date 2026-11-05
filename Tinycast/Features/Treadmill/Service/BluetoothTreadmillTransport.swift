import Foundation

@MainActor
protocol TreadmillBluetoothCentral: AnyObject {
    var onEvent: ((TreadmillBluetoothEvent) -> Void)? { get set }
    func start()
    func scan() -> Bool
    func connect()
    func write(_ data: Data) throws
    func stop()
}

enum TreadmillBluetoothEvent {
    case poweredOn, poweredOff, unauthorized, discovered, ready, disconnected
    case bytes(Data)
    case failed
}

enum TreadmillBluetoothFailure: LocalizedError, Equatable {
    case bluetoothOff, unauthorized, padAbsent, connectionFailed

    var errorDescription: String? {
        switch self {
        case .bluetoothOff: String(localized: "Bluetooth is turned off.", table: "Notchcast")
        case .unauthorized: String(localized: "Allow Bluetooth access in System Settings.", table: "Notchcast")
        case .padAbsent: String(localized: "No walking pad was found nearby.", table: "Notchcast")
        case .connectionFailed: String(localized: "Could not connect to the walking pad.", table: "Notchcast")
        }
    }
}

@MainActor
final class BluetoothTreadmillTransport: TreadmillTransport {
    var onBytes: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onReady: (() -> Void)?
    var onFailure: (((any Error)?) -> Void)?
    let maintainsConnection = true
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

    private func deadline(reconnect: Bool = false) {
        timeout?.cancel()
        timeout = Task { [weak self, timeoutDuration] in
            do { try await Task.sleep(for: timeoutDuration) } catch { return }
            guard !Task.isCancelled, let self, self.wanted, self.powered, !self.ready else { return }
            if reconnect {
                self.central.connect()
            } else {
                self.onFailure?(TreadmillBluetoothFailure.padAbsent)
                if self.central.scan() { self.deadline() }
            }
        }
    }

    private func receive(_ event: TreadmillBluetoothEvent) {
        guard wanted else { return }
        switch event {
        case .poweredOn:
            powered = true
            onFailure?(nil)
            if central.scan() { deadline() }
        case .discovered:
            timeout?.cancel()
            central.connect()
        case .ready:
            timeout?.cancel()
            ready = true
            onFailure?(nil)
            onReady?()
        case .bytes(let data):
            if ready { onBytes?(data) }
        case .disconnected:
            timeout?.cancel()
            ready = false
            onDisconnect?()
            if wanted, powered { central.connect() }
        case .failed:
            ready = false
            onDisconnect?()
            onFailure?(TreadmillBluetoothFailure.connectionFailed)
            deadline(reconnect: true)
        case .poweredOff, .unauthorized:
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
