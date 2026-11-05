import Foundation

@MainActor
struct TreadmillReminders {
    let enabled: () -> Bool
    let present: (String) -> Void

    func post(history: TreadmillHistoryStore, reachedGoal: Bool, now: Date, calendar: Calendar) -> Bool {
        guard enabled() else { return false }
        if reachedGoal { present(String(localized: "Daily walking goal reached.", table: "Notchcast")) }
        let odometer = history.summary(now: now, calendar: calendar).odometerKm
        guard let mark = history.archive.lubeDueMark(odometerKm: odometer) else { return reachedGoal }
        history.markLubricated(odometerKm: mark)
        present(String(localized: "Walking pad: time to lubricate the belt (\(Int(mark)) km).", table: "Notchcast"))
        return true
    }
}
