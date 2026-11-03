// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

nonisolated struct BatteryReading: Sendable, Equatable {
    let percent: Double?
    let isCharging: Bool
    let isCharged: Bool
    let onBattery: Bool
    let timeToEmptySeconds: Double?
    let timeToFullSeconds: Double?
    let cycleCount: Int?
    let designCapacity: Double?
    let maximumCapacity: Double?
    let healthPercent: Double?
    let temperatureCelsius: Double?
    let watts: Double?
    let adapterWatts: Double?

    static func decode(properties: [String: Any], source: [String: Any] = [:]) -> Self? {
        guard properties["BatteryInstalled"] as? Bool != false,
              source["Is Present"] as? Bool != false,
              !properties.isEmpty || !source.isEmpty else { return nil }
        func number(_ value: Any?) -> Double? {
            guard let value = value as? NSNumber, value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        func positive(_ value: Any?) -> Double? {
            number(value).flatMap { $0 > 0 ? $0 : nil }
        }
        func seconds(_ value: Any?) -> Double? {
            number(value).flatMap { (0..<10080).contains($0) ? $0 * 60 : nil }
        }
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        let charging = source["Is Charging"] as? Bool ?? properties["IsCharging"] as? Bool ?? false
        let external = (source["Power Source State"] as? String).map { $0 == "AC Power" }
            ?? properties["ExternalConnected"] as? Bool ?? charging
        let current = number(source["Current Capacity"] ?? properties["CurrentCapacity"])
        let maximum = positive(source["Max Capacity"] ?? properties["MaxCapacity"])
        let percent = current.flatMap { current in maximum.map { min(100, max(0, current / $0 * 100)) } }
        let design = positive(properties["DesignCapacity"] ?? data["DesignCapacity"])
        let full = positive(properties["NominalChargeCapacity"] ?? data["NominalChargeCapacity"])
            ?? positive(properties["AppleRawMaxCapacity"])
            ?? positive(properties["FullChargeCapacity"])
            ?? positive(properties["MaxCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        let health = full.flatMap { full in design.map { min(100, full / $0 * 100) } }
        let temperature = number(properties["Temperature"] ?? data["Temperature"] ?? data["VirtualTemperature"])
            .map { $0 / 100 }
            .flatMap { (-20...100).contains($0) ? $0 : nil }
        let currentNumber = (properties["Amperage"] ?? properties["InstantAmperage"]) as? NSNumber
        let amperage = currentNumber.map { value -> Double in
            let raw = value.int64Value
            return Double(raw > Int64(Int32.max) ? Int64(Int32(truncatingIfNeeded: raw)) : raw)
        }
        let watts = positive(properties["Voltage"]).flatMap { voltage in
            amperage.map { voltage * $0 / 1_000_000 }
        }
        let adapters = properties["AppleRawAdapterDetails"] as? [[String: Any]]
        let adapter = adapters?.first ?? properties["AppleRawAdapterDetails"] as? [String: Any]
            ?? properties["AdapterDetails"] as? [String: Any] ?? [:]
        let cycles = number(properties["CycleCount"]).flatMap { value -> Int? in
            (0...100000).contains(value) ? Int(value) : nil
        }
        return Self(
            percent: percent, isCharging: charging,
            isCharged: source["Is Charged"] as? Bool ?? properties["FullyCharged"] as? Bool ?? false,
            onBattery: !external && !charging,
            timeToEmptySeconds: !external && !charging
                ? seconds(source["Time to Empty"] ?? properties["AvgTimeToEmpty"]) : nil,
            timeToFullSeconds: charging
                ? seconds(source["Time to Full Charge"] ?? properties["AvgTimeToFull"]) : nil,
            cycleCount: cycles, designCapacity: design, maximumCapacity: full,
            healthPercent: health, temperatureCelsius: temperature, watts: watts,
            adapterWatts: external ? positive(adapter["Watts"]) : nil)
    }
}
