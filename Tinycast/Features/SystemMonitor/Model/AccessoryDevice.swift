import Foundation

nonisolated struct AccessoryDevice: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case headphones, keyboard, mouse, trackpad, other

        var symbol: String {
            switch self {
            case .headphones: "headphones"
            case .keyboard: "keyboard"
            case .mouse: "magicmouse"
            case .trackpad: "rectangle.and.hand.point.up.left"
            case .other: "dot.radiowaves.left.and.right"
            }
        }
    }

    let address: String
    let name: String
    let majorClass: UInt32
    let minorClass: UInt32

    var key: String { address.lowercased().filter { $0.isHexDigit } }

    var kind: Kind {
        Self.kind(name: name, majorClass: majorClass, minorClass: minorClass)
    }

    static func kind(name: String, majorClass: UInt32 = 0, minorClass: UInt32 = 0) -> Kind {
        let name = name.lowercased()
        if name.contains("trackpad") { return .trackpad }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if ["airpods", "headphone", "headset", "beats", "buds"].contains(where: name.contains) {
            return .headphones
        }
        if majorClass == 4, [1, 2, 6].contains(minorClass) { return .headphones }
        if majorClass == 5 {
            if minorClass & 0x10 != 0 { return .keyboard }
            if minorClass & 0x20 != 0 { return .mouse }
        }
        return .other
    }
}
