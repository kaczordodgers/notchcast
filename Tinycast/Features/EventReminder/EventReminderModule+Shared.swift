extension EventReminderModule {
    static let shared = EventReminderModule(store: AppCore.shared.calendarStore)
}
