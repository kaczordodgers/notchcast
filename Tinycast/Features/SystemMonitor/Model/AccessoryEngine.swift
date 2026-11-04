import Foundation

nonisolated struct AccessoryEngine: Sendable, Equatable {
    private var connected: Set<String>
    private var lastConnect: [String: TimeInterval] = [:]
    private var lowBattery: Set<UInt64> = []

    init(alreadyConnected: [AccessoryDevice] = []) {
        connected = Set(alreadyConnected.map(\.key).filter { !$0.isEmpty })
    }

    mutating func connect(_ device: AccessoryDevice, at time: TimeInterval) -> AccessoryEvent? {
        guard !device.key.isEmpty, time.isFinite else { return nil }
        guard connected.insert(device.key).inserted else { return nil }
        if let last = lastConnect[device.key], time - last < 0.4 { return nil }
        lastConnect[device.key] = time
        return .connected(device)
    }

    mutating func disconnect(_ device: AccessoryDevice) {
        connected.remove(device.key)
    }

    mutating func batteries(_ readings: [BatteryPeripheralReading]) -> [AccessoryEvent] {
        var events: [AccessoryEvent] = []
        for reading in readings {
            guard reading.percent.isFinite, (0...100).contains(reading.percent) else { continue }
            if reading.percent >= 25 { lowBattery.remove(reading.id) }
            if reading.percent <= 20, lowBattery.insert(reading.id).inserted {
                events.append(.lowBattery(reading, kind: AccessoryDevice.kind(name: reading.name)))
            }
        }
        return events
    }
}
