import Foundation

struct RemoteFanReport: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable {
        case auto, mid, max

        var next: Self {
            switch self {
            case .auto: .mid
            case .mid: .max
            case .max: .auto
            }
        }
    }

    struct Reading: Codable, Equatable, Sendable {
        let actual: Double
        let target: Double
        let minimum: Double
        let maximum: Double

        var middle: Double { minimum + 0.6 * (maximum - minimum) }

        func validate() throws {
            guard [actual, target, minimum, maximum].allSatisfy({ $0.isFinite && (0...20_000).contains($0) }),
                  maximum > minimum, maximum >= 1_000 else { throw Failure.invalidReport }
        }

        func matches(_ mode: Mode) -> Bool {
            switch mode {
            case .auto: true
            case .mid: abs(target - middle) < 25
            case .max: abs(target - maximum) < 25
            }
        }
    }

    let mode: Mode
    let fans: [Reading]

    func validate(for request: RemoteFanRequest) throws {
        guard (1...9).contains(fans.count) else { throw Failure.invalidReport }
        try fans.forEach { try $0.validate() }
        guard fans.allSatisfy({ $0.matches(mode) }) else { throw Failure.invalidReport }
        if let expected = Mode(rawValue: request.rawValue), expected != mode {
            throw Failure.invalidReport
        }
    }

    enum Failure: Error { case invalidReport, unavailable, busy }
}
