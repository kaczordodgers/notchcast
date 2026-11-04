import Foundation
import Observation

@MainActor @Observable
final class TreadmillPreferences {
    private(set) var goal: TreadmillGoal?
    @ObservationIgnored private let defaults: UserDefaults
    private static let goalKey = "treadmill.goal"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.goalKey) {
            goal = (try? JSONDecoder().decode(TreadmillGoal.self, from: data)).flatMap { $0.isValid ? $0 : nil }
        } else {
            goal = defaults.bool(forKey: "treadmill.goal.disabled") ? nil : .standard
        }
    }

    func setGoal(_ goal: TreadmillGoal?) throws {
        if let goal, !goal.isValid { throw TreadmillFailure.invalidHistory }
        let data = try goal.map { try JSONEncoder().encode($0) }
        defaults.set(data, forKey: Self.goalKey)
        defaults.set(goal == nil, forKey: "treadmill.goal.disabled")
        self.goal = goal
    }
}
