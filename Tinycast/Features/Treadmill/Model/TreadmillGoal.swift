import Foundation

struct TreadmillGoal: Codable, Equatable, Sendable {
    enum Unit: String, Codable, Sendable { case minutes, steps, kilometers }

    var unit: Unit
    var target: Double
    static let standard = Self(unit: .minutes, target: 60)

    var isValid: Bool { target.isFinite && (0.1...1_000_000).contains(target) }

    func progress(_ totals: TreadmillTotals) -> Double {
        guard isValid else { return 0 }
        let amount: Double
        switch unit {
        case .minutes: amount = totals.seconds / 60
        case .steps: amount = totals.steps
        case .kilometers: amount = totals.meters / 1000
        }
        return min(amount / target, 1)
    }
}
