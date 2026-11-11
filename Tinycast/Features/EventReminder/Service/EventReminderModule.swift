import AppKit
import EventKit
import Observation

extension DayCalendarService: EventReminderSource {
    func reminderEvents(in interval: DateInterval) -> [EventReminderEngine.Event] {
        records(in: interval).map { event, record in
            EventReminderEngine.Event(
                id: event.id, title: event.title, start: event.start, isAllDay: event.isAllDay, isDeclined: false,
                offsets: (record.alarms ?? []).filter { $0.absoluteDate == nil }.map(\.relativeOffset),
                tint: CGColorSpace(name: CGColorSpace.sRGB).flatMap {
                    record.calendar?.cgColor?.converted(to: $0, intent: .defaultIntent, options: nil)?.components
                }.map { $0.prefix(3).map(Double.init) },
                link: MeetingLink.detect(fields: [record.url?.absoluteString, record.location, record.notes])?.webURL)
        }
    }
}

@MainActor
final class EventReminderModule: NotchcastModule {
    nonisolated static let excludedCalendarsKey = "notchcast.day.excludedCalendars"
    let calendar: DayCalendarService
    private let center: IslandActivityCenter
    private var engine = EventReminderEngine(armedAt: .distantFuture)
    private var running = false
    private var generation = 0
    private var wake: Task<Void, Never>?
    private var observers: [NotificationToken] = []
    private var active: [(id: UUID, end: Date)] = []

    init(store: CalendarStore, center: IslandActivityCenter = .shared) {
        calendar = DayCalendarService(store: store, excludedKey: Self.excludedCalendarsKey)
        self.center = center
    }

    func start() {
        guard !running else { return }
        running = true
        generation += 1
        engine = EventReminderEngine(armedAt: Date())
        let notifications = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSSystemClockDidChange,
                     .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationToken(notifications.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }, center: notifications))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(NotificationToken(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }, center: workspace))
        track(generation)
    }

    func stop() {
        running = false
        generation += 1
        wake?.cancel()
        wake = nil
        observers = []
        calendar.stop()
        active.forEach { center.finish($0.id) }
        active = []
    }

    private func track(_ token: Int) {
        guard running, generation == token else { return }
        refresh()
        withObservationTracking {
            _ = calendar.store.access
            _ = calendar.revision
        } onChange: { [weak self] in
            Task { @MainActor in self?.track(token) }
        }
    }

    private func refresh() {
        guard running else { return }
        wake?.cancel()
        let now = Date()
        let math = Calendar.current
        let midnight = math.date(byAdding: .day, value: 1, to: math.startOfDay(for: now))!
        let end = math.date(byAdding: .day, value: 8, to: math.startOfDay(for: now))!
        let events = calendar.reminderEvents(in: DateInterval(start: now.addingTimeInterval(-300), end: end))
        let result = engine.evaluate(events: events, now: now)
        active.filter { $0.end <= now }.forEach { center.finish($0.id) }
        active.removeAll { $0.end <= now }
        for alert in result.due {
            let expiry = now.addingTimeInterval(10)
            let id = center.begin(IslandActivity(
                kind: .status, title: alert.event.title, symbol: "calendar",
                meeting: .init(start: alert.event.start, tint: alert.event.tint, link: alert.event.link)))
            active.append((id, expiry))
        }
        let target = ([midnight] + [result.next].compactMap { $0 } + active.map(\.end)).min()!
        wake = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, target.timeIntervalSinceNow)))
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
