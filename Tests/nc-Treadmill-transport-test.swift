// notchcast-sources: Tinycast/Features/Treadmill/Model/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
import Foundation

@MainActor
private final class FakeCentral: TreadmillBluetoothCentral {
    var onEvent: ((TreadmillBluetoothEvent) -> Void)?
    var scans = 0
    var connects = 0
    var stops = 0
    var writes: [Data] = []
    func start() { onEvent?(.poweredOn) }
    func scan() { scans += 1 }
    func connect() { connects += 1 }
    func stop() { stops += 1 }
    func write(_ data: Data) throws { writes.append(data) }
}

@main @MainActor
struct TreadmillTransportTests {
    static func main() async throws {
        let central = FakeCentral()
        let transport = BluetoothTreadmillTransport(central: central, timeout: .milliseconds(10))
        var received: [Data] = []
        var disconnects = 0
        var failure: TreadmillBluetoothFailure?
        transport.onBytes = { received.append($0) }
        transport.onDisconnect = { disconnects += 1 }
        transport.onFailure = { failure = $0 as? TreadmillBluetoothFailure }
        try transport.open()
        precondition(central.scans == 1)
        central.onEvent?(.discovered)
        precondition(central.connects == 1)
        central.onEvent?(.ready)
        let bytes = TreadmillProtocol.queryStatus
        central.onEvent?(.bytes(bytes))
        precondition(received == [bytes])
        try transport.send(bytes)
        precondition(central.writes == [bytes])
        central.onEvent?(.disconnected)
        precondition(disconnects == 1 && central.connects == 2)
        central.onEvent?(.ready)
        central.onEvent?(.poweredOff)
        precondition(failure == .bluetoothOff && disconnects == 2)
        central.onEvent?(.poweredOn)
        precondition(failure == nil)
        let scans = central.scans
        let stops = central.stops
        try await Task.sleep(for: .milliseconds(30))
        precondition(failure == .padAbsent)
        precondition(central.scans > scans && central.stops == stops)
        try transport.open()
        central.onEvent?(.discovered)
        let connects = central.connects
        try await Task.sleep(for: .milliseconds(30))
        precondition(central.connects == connects && central.stops == stops)
        central.onEvent?(.failed)
        precondition(failure == .connectionFailed)
        try await Task.sleep(for: .milliseconds(30))
        precondition(central.connects == connects + 1 && central.stops == stops)
        central.onEvent?(.failed)
        precondition(failure == .connectionFailed)
        try await Task.sleep(for: .milliseconds(30))
        precondition(central.connects == connects + 2)
        transport.close()
        try transport.open()
        precondition(central.scans > scans + 1)
        central.onEvent?(.unauthorized)
        precondition(failure == .unauthorized)
        transport.close()
        central.onEvent?(.discovered)
        precondition(central.connects == connects + 2)
        precondition(CoreBluetoothTreadmillCentral.service.uuidString == "FFF0")
        precondition(CoreBluetoothTreadmillCentral.notify.uuidString == "FFF1")
        precondition(CoreBluetoothTreadmillCentral.write.uuidString == "FFF2")
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = UserDefaults(suiteName: "treadmill-test-" + UUID().uuidString)!
        let coordinator = TreadmillCoordinator(transport: BluetoothTreadmillTransport(central: FakeCentral()),
            history: TreadmillHistoryStore(repository: TreadmillRepository(directory: folder)),
            preferences: TreadmillPreferences(defaults: defaults))
        let index = AgentActionIndex()
        coordinator.configure(index: index)
        precondition(index.actionIDs.isEmpty)
        coordinator.setEnabled(.walk, true)
        precondition(index.actionIDs.count == 5 && index.stateIDs == ["device.treadmill"])
        coordinator.setEnabled(.walk, false)
        precondition(index.actionIDs.isEmpty && index.stateIDs.isEmpty)
        print("Treadmill registration passed: on registers five actions; off removes actions and state")
        print("Treadmill transport passed: scan retries, pending connect, repeated failure retries, close/open recovery, bytes, writes")
    }
}
