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
    var known = false
    func start() { onEvent?(.poweredOn) }
    func scan() -> Bool {
        if known { connect(); return false }
        scans += 1
        return true
    }
    func connect() { connects += 1 }
    func stop() { stops += 1 }
    func write(_ data: Data) throws { writes.append(data) }
}

@main @MainActor
struct TreadmillTransportTests {
    static func waitUntil(_ condition: () -> Bool, line: UInt = #line) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        precondition(condition(), "Timed out", line: line)
    }

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
        try await waitUntil { failure == .padAbsent && central.scans > scans }
        precondition(central.stops == stops)
        try transport.open()
        central.onEvent?(.discovered)
        let connects = central.connects
        try await Task.sleep(for: .milliseconds(30))
        precondition(central.connects == connects && central.stops == stops)
        central.onEvent?(.failed)
        precondition(failure == .connectionFailed)
        try await waitUntil { central.connects == connects + 1 }
        precondition(central.stops == stops)
        central.onEvent?(.failed)
        precondition(failure == .connectionFailed)
        try await waitUntil { central.connects == connects + 2 }
        let rejectedScans = central.scans
        failure = nil
        central.onEvent?(.rejected)
        precondition(central.scans == rejectedScans + 1)
        try await waitUntil { failure == .padAbsent }
        print("Treadmill rejection passed: rejected pad rescans and the pad-absent timeout runs again")
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
        let known = FakeCentral()
        known.known = true
        let pending = BluetoothTreadmillTransport(central: known, timeout: .milliseconds(10))
        try pending.open()
        try await waitUntil { known.connects == 1 }
        precondition(known.scans == 0)
        pending.close()
        print("Treadmill recovery passed: known pad has no scans and one pending connect")
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
        let overLimit = Double(TreadmillProtocol.maximumMinutes + 1)
        for (operation, fields): (String, [String: AgentJSON]) in [
            ("start", ["speed": .number(4), "minutes": .number(overLimit)]),
            ("speed", ["speed": .number(TreadmillProtocol.speedRange.upperBound + 1)]), ("jump", [:]),
        ] {
            do {
                _ = try await coordinator.perform(operation, parameters: .object(fields))
                preconditionFailure("\(operation) accepted a value outside the pad's limits")
            } catch let code as AgentReply.Code { precondition(code == .badRequest) }
        }
        coordinator.setEnabled(.walk, false)
        precondition(index.actionIDs.isEmpty && index.stateIDs.isEmpty)
        print("Treadmill registration passed: on registers five actions; off removes actions and state")
        print("Treadmill transport passed: scan retries, pending connect, repeated failure retries, close/open recovery, bytes, writes")
    }
}
