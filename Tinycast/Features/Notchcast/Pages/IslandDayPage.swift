import SwiftUI

@MainActor
@Observable
final class IslandDayPage {
    let store: CalendarStore
    let clock: MeetingClock
    private let calendar: CalendarCoordinator
    private let settings: AppSettings
    private let openSettings: () -> Void
    private let closeIsland: () -> Void
    private var selectedID: MeetingEvent.ID?
    private(set) var scroll = ScrollIntent(kind: .top)

    init(store: CalendarStore, clock: MeetingClock, calendar: CalendarCoordinator,
         settings: AppSettings, openSettings: @escaping () -> Void, close: @escaping () -> Void) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.settings = settings
        self.openSettings = openSettings
        closeIsland = close
    }

    var hasAccess: Bool {
        settings.calendarEnabled && NotchcastPreferences.shared.isOn(.dayCalendar) && store.access == .granted
    }
    var events: [MeetingEvent] {
        hasAccess ? UpcomingWindow.agenda(from: store.events, now: clock.now) : []
    }
    var selection: MeetingEvent.ID? {
        IslandPageFocus.selection(in: events.map(\.id), stored: selectedID)
    }

    func refresh() {
        guard settings.calendarEnabled && NotchcastPreferences.shared.isOn(.dayCalendar) else { return }
        store.refreshAccess()
        store.reload()
    }

    func reloadIfStale() {
        guard settings.calendarEnabled && NotchcastPreferences.shared.isOn(.dayCalendar) else { return }
        store.reloadIfStale(now: clock.now)
    }

    func moveSelection(_ delta: Int) {
        guard let next = IslandPageFocus.row(in: events.map(\.id), from: selectedID, by: delta) else { return }
        selectedID = next
        scroll = ScrollIntent(kind: .follow)
    }

    /// Without access the page's one control is Settings, so Return reaches it as a click does.
    func activate() {
        guard hasAccess else { return showSettings() }
        guard let meeting = events.first(where: { $0.id == selection }) else { return }
        activate(meeting)
    }

    func activate(_ meeting: MeetingEvent) {
        closeIsland()
        calendar.activateMeeting(id: meeting.id)
    }

    func showSettings() { openSettings() }
}
