import Foundation

extension NotchcastFeature.BackupKeys {
    static let eventReminder = Self(allowed: [
        "notchcast.day.excludedCalendars": .strings(500, 256),
    ], excluded: [], snapshot: {
        ["notchcast.day.excludedCalendars": EventReminderModule.shared.calendar.excludedCalendarIDs.sorted()]
    }, apply: { values in
        if let value = values["notchcast.day.excludedCalendars"] as? [String] {
            EventReminderModule.shared.calendar.setExcludedCalendars(Set(value))
        }
    })
}
