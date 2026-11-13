// notchcast-sources: Tinycast/Features/LiveDay/DayCalendarService.swift
// notchcast-sources: Tinycast/Features/LiveDay/Model/DayEvent.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import EventKit
import Observation

@main
struct DayCalendarMappingTest {
    @MainActor static func main() {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.calendar = EKCalendar(for: .event, eventStore: eventStore)
        event.title = "Test meeting"
        event.startDate = Date(timeIntervalSince1970: 10_000)
        event.endDate = event.startDate.addingTimeInterval(60)
        event.isAllDay = true
        let mapped = DayCalendarService.dayEvent(event)!
        precondition(mapped.title == event.title && mapped.start == event.startDate)
        precondition(mapped.end == event.endDate && mapped.isAllDay)
        precondition(mapped.calendarID == event.calendar.calendarIdentifier)
        event.endDate = nil
        precondition(DayCalendarService.dayEvent(event) == nil)
        print("PASS EventKit dates, title, all-day and calendar mapping; incomplete event rejected")
    }
}

@MainActor @Observable
final class CalendarStore {
    enum Access { case granted, denied }
    var access = Access.denied
    func refreshAccess() {}
}
