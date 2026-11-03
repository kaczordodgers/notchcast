import Foundation
import IOKit.ps

nonisolated struct BatteryService: Sendable {
    func read() -> BatteryReading? {
        var source: [String: Any] = [:]
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in sources {
                if let values = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue()
                    as? [String: Any], values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                    source = values
                    break
                }
            }
        }
        let readings: [BatteryReading] = PowerRegistryAccess.read("AppleSmartBattery") { _, values in
            var properties = values
            if properties["AppleRawAdapterDetails"] == nil, properties["AdapterDetails"] == nil {
                properties["AdapterDetails"] = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()
            }
            return BatteryReading.decode(properties: properties, source: source)
        }
        return readings.first ?? (source.isEmpty ? nil : BatteryReading.decode(properties: [:], source: source))
    }
}
