import Foundation

nonisolated enum AccessoryBatteryRows {
    static func make(_ readings: [BatteryPeripheralReading]) -> [BatteryPeripheralReading] {
        var seen = Set<UInt64>()
        return readings.filter {
            !$0.name.isEmpty && $0.percent.isFinite && (0...100).contains($0.percent)
                && seen.insert($0.id).inserted
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }
}
