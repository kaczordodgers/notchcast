extension NotchcastBackupState {
    static let dayCalendar = Self(snapshot: {
        ["notchcast.day.excludedCalendars": EventReminderModule.shared.calendar.excludedCalendarIDs.sorted()]
    }, apply: { values in
        if let value = values["notchcast.day.excludedCalendars"] as? [String] {
            EventReminderModule.shared.calendar.setExcludedCalendars(Set(value))
        }
    })
}
