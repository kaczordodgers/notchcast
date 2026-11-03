import Foundation

nonisolated struct MemoryReading: Sendable, Equatable {
    enum Pressure: Sendable, Equatable {
        case normal, warning, critical

        init?(rawValue: Int32) {
            switch rawValue {
            case 1: self = .normal
            case 2: self = .warning
            case 4: self = .critical
            default: return nil
            }
        }
    }

    let total: UInt64
    let used: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let free: UInt64
    let pressure: Pressure?
    let pressurePercent: Double?
    let swapUsed: UInt64?
    let swapTotal: UInt64?
}
