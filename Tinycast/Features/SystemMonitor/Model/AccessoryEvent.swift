import Foundation

nonisolated enum AccessoryEvent: Sendable, Equatable {
    case connected(AccessoryDevice)
    case lowBattery(BatteryPeripheralReading, kind: AccessoryDevice.Kind)
}
