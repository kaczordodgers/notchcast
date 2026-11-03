import Foundation

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
