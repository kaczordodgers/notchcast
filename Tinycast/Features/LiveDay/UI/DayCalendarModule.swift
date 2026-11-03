@MainActor
final class DayCalendarModule: NotchcastModule {
    let service = DayCalendarService(store: CalendarStore())

    func start() {
        service.start()
    }

    func stop() {
        service.stop()
        service.store.stop()
    }
}
