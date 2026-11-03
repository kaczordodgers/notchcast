// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

nonisolated struct BatteryPeripheralService: Sendable {
    func read() -> [BatteryPeripheralReading] {
        var seen = Set<UInt64>()
        return ["AppleDeviceManagementHIDEventService", "IOHIDDevice"].flatMap { className in
            PowerRegistryAccess.read(className) { entry, properties -> BatteryPeripheralReading? in
                let id = PowerRegistryAccess.id(entry)
                guard seen.insert(id).inserted else { return nil }
                return BatteryPeripheralReading.decode(id: id, properties: properties)
            }
        }
    }
}
