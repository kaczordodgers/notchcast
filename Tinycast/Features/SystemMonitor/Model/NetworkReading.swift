import Foundation

nonisolated struct NetworkInterfaceCandidate: Sendable, Equatable {
    let name: String
    let isRunning: Bool
    let hasAddress: Bool

    static func select(_ interfaces: [Self], primaryNames: [String]) -> String? {
        let eligible = interfaces.filter { $0.name.hasPrefix("en") && $0.isRunning && $0.hasAddress }
        for name in primaryNames where eligible.contains(where: { $0.name == name }) { return name }
        return eligible.first?.name
    }
}

nonisolated struct NetworkReading: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case wifi, ethernet, other }

    let interface: String
    let kind: Kind
    let addresses: [String]
    let downBytesPerSecond: Double?
    let upBytesPerSecond: Double?
    let totalDown: UInt64
    let totalUp: UInt64
}
