import Foundation

@main
struct TweakSessionTests {
    static func main() throws {
        enum Failure: Error { case refused }
        let first = TweakPreference(domain: "test", key: "first")
        let second = TweakPreference(domain: "test", key: "second")
        var readings: [TweakPreference: TweakValue] = [first: .absent, second: .bool(false)]
        let plan = try MacSetupPlan(desired: [(first, .integer(2)), (second, .bool(true))], readings: readings)
        var session = TweakPlanSession()
        do {
            try session.apply(plan) { preference, value in
                if preference == second { throw Failure.refused }
                readings[preference] = value
            }
            preconditionFailure("Expected partial failure")
        } catch Failure.refused {}
        precondition(session.completed.count == 1)
        var drifted = readings
        drifted[first] = .integer(3)
        do {
            try session.undo(readings: drifted) { _, _ in preconditionFailure("Drift must prevent writes") }
            preconditionFailure("Expected drift")
        } catch MacSetupPlan.Failure.drift {}
        try session.undo(readings: readings) { readings[$0] = $1 }
        precondition(readings[first] == .absent && session.completed.isEmpty)
        try session.apply(plan) { readings[$0] = $1 }
        do {
            try session.undo(readings: readings) { _, _ in throw Failure.refused }
            preconditionFailure("Expected undo failure")
        } catch Failure.refused {}
        precondition(session.completed.count == 2)
        try session.undo(readings: readings) { readings[$0] = $1 }
        precondition(readings == [first: .absent, second: .bool(false)])
        print("Tweak session: partial apply, drift protection, retry and restoration passed")
    }
}
