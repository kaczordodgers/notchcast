import Foundation
import EventKit
import Observation

@MainActor
@Observable
final class DayCalendarService {
    let store: CalendarStore
    private(set) var revision = 0
    @ObservationIgnored private var rangeStore: EKEventStore?
    @ObservationIgnored private var observer: NotificationToken?

    init(store: CalendarStore) {
        self.store = store
    }

    /// Each visible event with its EventKit record, for a caller that needs alarms, colour or links.
    func records(in interval: DateInterval) -> [(event: DayEvent, record: EKEvent)] {
        _ = revision
        store.refreshAccess()
        guard store.access == .granted, interval.duration > 0 else { return [] }
        let eventStore = rangeStore ?? EKEventStore()
        rangeStore = eventStore
        observeChanges(eventStore)
        let calendars = eventStore.calendars(for: .event)
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: calendars)
        return eventStore.events(matching: predicate).compactMap { event in
            guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
                !((event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined })
            else { return nil }
            return (DayEvent(id: event.calendarItemIdentifier + "|\(start.timeIntervalSinceReferenceDate)",
                             title: event.title ?? String(localized: "(No Title)"), start: start, end: end,
                             isAllDay: event.isAllDay, calendarID: event.calendar.calendarIdentifier), event)
        }
    }

    func stop() {
        observer = nil
        rangeStore = nil
    }

    private func observeChanges(_ eventStore: EKEventStore) {
        guard observer == nil else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
        observer = NotificationToken(token, center: center)
    }
}
