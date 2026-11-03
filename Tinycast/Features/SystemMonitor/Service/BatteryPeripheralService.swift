// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation
import IOKit

nonisolated struct BatteryPeripheralService: Sendable {
    func read() -> [BatteryPeripheralReading] {
        var seen = Set<UInt64>()
        return ["AppleDeviceManagementHIDEventService", "IOHIDDevice"].flatMap { className in
            PowerRegistryAccess.read(className, copyAll: false) { entry, _ -> BatteryPeripheralReading? in
                let id = PowerRegistryAccess.id(entry)
                guard IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() != nil,
                      seen.insert(id).inserted else { return nil }
                return BatteryPeripheralReading.decode(id: id, properties: PowerRegistryAccess.properties(entry))
            }
        }
    }
}
