import Foundation

nonisolated enum TweakValue: Codable, Equatable, Sendable {
    case absent, bool(Bool), integer(Int), string(String)

    var object: Any? {
        switch self {
        case .absent: nil
        case .bool(let value): value
        case .integer(let value): value
        case .string(let value): value
        }
    }
}
