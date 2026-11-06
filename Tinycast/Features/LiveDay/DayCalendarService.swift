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
    private let defaults: UserDefaults
    private var excludedIDs: Set<String>
    var excludedCalendarIDs: Set<String> { excludedIDs }
    private let excludedKey = "notchcast.day.excludedCalendars"

    init(store: CalendarStore, defaults: UserDefaults = DayStorage.defaults) {
        self.store = store
        self.defaults = defaults
        excludedIDs = Set(defaults.stringArray(forKey: "notchcast.day.excludedCalendars") ?? [])
    }

    func start() {
        store.span = .nextSevenDays
        store.start()
    }

    func requestAccessFromButton() async -> Bool {
        let granted = await store.requestAccess()
        observer = nil
        rangeStore = nil
        return granted
    }

    func events(in interval: DateInterval) -> [DayEvent] {
        _ = revision
        store.refreshAccess()
        guard store.access == .granted, interval.duration > 0 else { return [] }
        let eventStore = rangeStore ?? EKEventStore()
        rangeStore = eventStore
        observeChanges(eventStore)
        let calendars = eventStore.calendars(for: .event).filter { !excludedIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: calendars)
        return eventStore.events(matching: predicate).compactMap { event -> DayEvent? in
            guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
                !((event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined })
            else { return nil }
            return DayEvent(id: event.calendarItemIdentifier + "|\(start.timeIntervalSinceReferenceDate)",
                            title: event.title ?? String(localized: "(No Title)"), start: start, end: end,
                            isAllDay: event.isAllDay, calendarID: event.calendar.calendarIdentifier)
        }.sorted { $0.start < $1.start }
    }

    func stop() {
        observer = nil
        rangeStore = nil
    }

    func reminderEvents(in interval: DateInterval) -> [EventReminderEngine.Event] {
        let visible = Set(events(in: interval).map(\.id))
        guard let rangeStore, !visible.isEmpty else { return [] }
        let predicate = rangeStore.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil)
        return rangeStore.events(matching: predicate).compactMap { event in
            guard let start = event.startDate else { return nil }
            let id = event.calendarItemIdentifier + "|\(start.timeIntervalSinceReferenceDate)"
            guard visible.contains(id) else { return nil }
            return EventReminderEngine.Event(
                id: id, title: event.title ?? String(localized: "(No Title)"), start: start,
                isAllDay: event.isAllDay, isDeclined: false,
                offsets: (event.alarms ?? []).filter { $0.absoluteDate == nil }.map(\.relativeOffset),
                tint: CGColorSpace(name: CGColorSpace.sRGB).flatMap {
                    event.calendar?.cgColor?.converted(to: $0, intent: .defaultIntent, options: nil)?.components
                }.map { $0.prefix(3).map(Double.init) },
                link: MeetingLink.detect(fields: [event.url?.absoluteString, event.location, event.notes])?.webURL)
        }
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

    func setExcludedCalendars(_ ids: Set<String>) {
        excludedIDs = ids
        defaults.set(Array(ids), forKey: excludedKey)
        revision += 1
    }

    func refresh() {
        store.reload()
        revision += 1
    }

    var events: [DayEvent] {
        store.events.filter { !excludedIDs.contains($0.calendarID) && !$0.isDeclined }.map {
            DayEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: $0.isAllDay, calendarID: $0.calendarID)
        }
    }
}
