import Foundation

nonisolated struct MonitorCadence: Sendable, Equatable {
    let interval: TimeInterval
    let leeway: TimeInterval

    static func next(isVisible: Bool, baseInterval: TimeInterval = 2) -> MonitorCadence? {
        guard isVisible, baseInterval.isFinite, baseInterval > 0 else { return nil }
        return MonitorCadence(interval: baseInterval, leeway: baseInterval * 0.1)
    }
}
