import Foundation

/// The one value a closed island shows beside an ongoing thing: the most exact thing its state knows
/// (look-decisions, "Value per ongoing state"). Every closed state renders through `IslandValueText`.
indirect enum IslandValue: Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        case none
        case megabitsPerSecond
    }

    case timeLeft(Date)
    case elapsed(since: Date)
    case elapsedFrozen(TimeInterval)
    case percent(Double)
    /// X/Y items or files.
    case count(Int, of: Int)
    /// A stage of a longer job: "Step X/Y".
    case step(Int, of: Int)
    case live(Double, Unit)
    case toggle(Bool)
    /// An input level, 0 to 1, drawn as still bars.
    case level(Double)
    case spinner
    /// Two values that both matter, the first leading: battery calibration's percent and step.
    case pair(IslandValue, IslandValue)

    /// Percent, level and counts clamped once here, so no view rechecks them.
    static func clamped(_ value: Self) -> Self {
        switch value {
        case .percent(let share): .percent(min(max(share.isFinite ? share : 0, 0), 1))
        case .level(let share): .level(min(max(share.isFinite ? share : 0, 0), 1))
        case .count(let done, let total): .count(max(0, min(done, total)), of: max(0, total))
        case .step(let done, let total): .step(max(0, min(done, total)), of: max(0, total))
        case .live(let number, let unit): .live(number.isFinite ? max(0, number) : 0, unit)
        case .elapsedFrozen(let seconds): .elapsedFrozen(max(0, seconds))
        case .pair(let first, let second): .pair(clamped(first), clamped(second))
        default: value
        }
    }

    /// What an activity without an explicit value shows: its end date, then its progress, else a spinner.
    static func fallback(progress: Double?, endDate: Date?) -> Self {
        if let endDate { return .timeLeft(endDate) }
        if let progress { return clamped(.percent(progress)) }
        return .spinner
    }

    /// A share of 0 to 1 a ring can draw, when the value is one.
    var share: Double? {
        switch self {
        case .percent(let share), .level(let share): share
        case .count(let done, let total), .step(let done, let total): total > 0 ? Double(done) / Double(total) : nil
        case .pair(let first, _): first.share
        default: nil
        }
    }
}
