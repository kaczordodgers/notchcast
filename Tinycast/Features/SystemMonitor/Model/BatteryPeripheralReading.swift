import Foundation

nonisolated struct BatteryPeripheralReading: Sendable, Equatable {
    let id: UInt64
    let name: String
    let percent: Double
    var isCharging: Bool?

    static func decode(id: UInt64, properties: [String: Any]) -> Self? {
        guard properties["Built-In"] as? Bool != true,
              properties["Connected"] as? Bool != false,
              let name = (properties["Product"] ?? properties["ProductName"]
                ?? properties["Name"]) as? String, !name.isEmpty,
              let percent = (properties["BatteryPercent"] as? NSNumber)?.doubleValue,
              percent.isFinite, (0...100).contains(percent) else { return nil }
        return Self(id: id, name: name, percent: percent,
                    isCharging: properties["BatteryIsCharging"] as? Bool)
    }
}
