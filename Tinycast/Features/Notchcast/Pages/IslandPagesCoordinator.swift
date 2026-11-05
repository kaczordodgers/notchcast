import SwiftUI

@MainActor
@Observable
final class IslandPagesCoordinator {
    var isRefreshing: Bool { refreshState.isRefreshing }
    private let refreshState = IslandPageRefresh(minimumVisible: .seconds(Theme.Duration.copyFeedback))
    private var homeRevision = UUID()
    var headerFocus: Int?
    private var homeSelectionID: IslandActivity.ID?
    private(set) var homeScroll = ScrollIntent(kind: .top)
    let pages = IslandPage.allCases
    @ObservationIgnored private let day: IslandDayPage
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private weak var island: IslandController?

    init(core: AppCore, island: IslandController) {
        self.island = island
        openSettings = { [weak core, weak island] in
            island?.close()
            core?.settingsCoordinator.showSettings(tab: .notchcast)
        }
        let day = IslandDayPage(
            store: core.calendarStore, clock: MeetingClock(), calendar: core.calendarCoordinator,
            settings: core.settings,
            openSettings: { [weak core, weak island] in
                island?.close()
                core?.settingsCoordinator.showSettings(tab: .calendar)
            }, close: { [weak island] in island?.close() })
        self.day = day
        day.clock.onTick = { [weak day] in day?.reloadIfStale() }
    }

    func content(_ page: IslandPage) -> AnyView {
        page.content(day: day, homeRevision: homeRevision)
    }

    /// One highlight at a time: Return acts on the header's ring while it shows, else on the list's row.
    var focusesHeader: Bool { headerFocus != nil && island?.hasKeyboardFocus == true }

    private var activities: [IslandActivity] {
        NotchcastPreferences.shared.isOn(.islandLiveActivities) ? IslandActivityCenter.shared.activities : []
    }

    var homeSelection: IslandActivity.ID? {
        IslandPageFocus.selection(in: activities.map(\.id), stored: homeSelectionID)
    }

    func didOpen(page: IslandPage) {
        headerFocus = nil
        homeSelectionID = nil
        homeScroll = ScrollIntent(kind: .top)
        cancelRefresh()
        if page == .day { day.reloadIfStale() }
        day.clock.start()
    }

    func didClose() {
        cancelRefresh()
        headerFocus = nil
        day.clock.stop()
    }

    /// The whole key map of an open page, so the panel's handler only forwards what `IslandKey` read.
    func perform(_ key: IslandKey, in island: IslandController) -> Bool {
        switch key {
        case .ignored: break
        case .pin: island.togglePin()
        case .refresh: refresh(island.page)
        case .close: island.close()
        case let .page(target):
            if target == island.page { island.close() } else { island.selectPage(target) }
        case let .header(delta): moveHeader(delta)
        case let .selection(delta): moveSelection(delta, page: island.page)
        case .activate: activateHeader(in: island)
        }
        return true
    }

    func refresh(_ page: IslandPage) {
        refreshState.run { [weak self] in
            guard let self else { return }
            await page.refresh(home: { homeRevision = UUID() }, day: { day.refresh() })
        }
    }

    func cancelRefresh() {
        refreshState.cancel()
    }

    func moveHeader(_ delta: Int) {
        headerFocus = IslandPageFocus.header(after: headerFocus, shown: island?.page ?? .home, delta: delta)
    }

    func activateHeader(in island: IslandController) {
        guard let headerFocus else {
            switch island.page {
            case .home: activateHome()
            case .day: day.activate()
            }
            return
        }
        if pages.indices.contains(headerFocus) {
            if pages[headerFocus] == island.page { self.headerFocus = nil } else { island.selectPage(pages[headerFocus]) }
        } else if headerFocus == pages.count {
            island.togglePin()
        } else { showSettings() }
    }

    func moveSelection(_ delta: Int, page: IslandPage) {
        headerFocus = nil
        switch page {
        case .home:
            guard let next = IslandPageFocus.row(in: activities.map(\.id), from: homeSelectionID, by: delta)
            else { return }
            homeSelectionID = next
            homeScroll = ScrollIntent(kind: .follow)
        case .day: day.moveSelection(delta)
        }
    }

    /// Return runs the selected card's button; a row without one has nothing to do.
    private func activateHome() {
        guard let id = homeSelection, activities.first(where: { $0.id == id })?.action != nil else { return }
        IslandActivityCenter.shared.perform(id)
    }

    func showSettings() { openSettings() }
}
