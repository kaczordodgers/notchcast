import Foundation

nonisolated struct AccessoryNoticeEngine {
    private var connected: Set<String> = []
    private var low: Set<UInt64> = []

    mutating func seed(_ addresses: [String]) { connected = Set(addresses.map(Self.key)) }

    mutating func connection(_ address: String, connected value: Bool) -> Bool {
        let key = Self.key(address)
        guard !key.isEmpty else { return false }
        if !value { connected.remove(key); return false }
        return connected.insert(key).inserted
    }

    mutating func batteries(_ readings: [BatteryPeripheralReading]) -> [BatteryPeripheralReading] {
        AccessoryBatteryRows.make(readings).filter { reading in
            if reading.percent >= 25 { low.remove(reading.id) }
            return reading.percent <= 20 && low.insert(reading.id).inserted
        }
    }

    private static func key(_ value: String) -> String { value.lowercased().filter(\.isHexDigit) }
}
