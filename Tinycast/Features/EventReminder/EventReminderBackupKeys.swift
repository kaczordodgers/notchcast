import Foundation

extension NotchcastFeature.BackupKeys {
    static let eventReminder = Self(allowed: [
        EventReminderModule.excludedCalendarsKey: .strings(500, 256),
    ], excluded: [], snapshot: {
        [EventReminderModule.excludedCalendarsKey: EventReminderModule.shared.calendar.excludedCalendarIDs.sorted()]
    }, apply: { values in
        if let value = values[EventReminderModule.excludedCalendarsKey] as? [String] {
            EventReminderModule.shared.calendar.setExcludedCalendars(Set(value))
        }
    })
}
