import Foundation

nonisolated struct SMCValue: Sendable, Equatable {
    struct KeyInfo: Sendable, Equatable {
        let size: Int
        let type: String
        let attributes: UInt8
    }

    let info: KeyInfo
    let bytes: [UInt8]

    var number: Double? {
        guard bytes.count == info.size, (1...4).contains(bytes.count) else { return nil }
        let unsigned = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let value: Double
        switch (info.type, bytes.count) {
        case ("flt ", 4):
            let bits = bytes.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            value = Double(Float(bitPattern: bits))
        case ("fpe2", 2): value = Double(unsigned) / 4
        case ("sp78", 2): value = Double(Int16(bitPattern: UInt16(unsigned))) / 256
        case ("ui8 ", 1), ("ui16", 2), ("ui32", 4): value = Double(unsigned)
        case ("si8 ", 1): value = Double(Int8(bitPattern: UInt8(unsigned)))
        case ("si16", 2): value = Double(Int16(bitPattern: UInt16(unsigned)))
        default: return nil
        }
        return value.isFinite ? value : nil
    }
}
