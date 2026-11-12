import SwiftUI

@MainActor
@Observable
final class IslandPagesCoordinator {
    var isRefreshing: Bool { refreshState.isRefreshing }
    private let refreshState = IslandPageRefresh()
    private var homeRevision = UUID()
    var headerFocus: Int?
    var pages: [IslandPage] { IslandPage.allCases.filter { $0.isAvailable } }
    @ObservationIgnored private let day: IslandDayPage
    @ObservationIgnored private let openSettings: () -> Void

    init(core: AppCore, island: IslandController) {
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

    #if DEBUG
    func noAccessContent() -> AnyView {
        AnyView(IslandDayView(page: day, hasAccess: false))
    }
    #endif

    func didOpen(page: IslandPage) {
        headerFocus = nil
        cancelRefresh()
        if page == .day { day.reloadIfStale() }
        if page == .usage, NotchcastCore.aiUsage.needsRefresh { refresh(page) }
        day.clock.start()
    }

    func didClose() {
        cancelRefresh()
        headerFocus = nil
        day.clock.stop()
    }

    func refresh(_ page: IslandPage) {
        refreshState.run { [weak self] in
            guard let self else { return }
            await page.refresh(
                home: { homeRevision = UUID() }, day: { day.refresh() },
                usage: { try? await NotchcastCore.aiUsage.refresh() })
        }
    }

    func cancelRefresh() {
        refreshState.cancel()
    }

    func moveHeader(_ delta: Int) {
        let count = pages.count + 2
        headerFocus = ((headerFocus ?? (delta > 0 ? -1 : 0)) + delta + count) % count
    }

    func activateHeader(in island: IslandController) {
        guard let headerFocus else {
            if island.page == .day { day.activate() }
            return
        }
        if pages.indices.contains(headerFocus) {
            island.selectPage(pages[headerFocus])
        } else if headerFocus == pages.count {
            island.togglePin()
        } else { showSettings() }
    }

    func moveSelection(_ delta: Int, page: IslandPage) {
        headerFocus = nil
        if page == .day { day.moveSelection(delta) }
    }

    func showSettings() { openSettings() }
}
