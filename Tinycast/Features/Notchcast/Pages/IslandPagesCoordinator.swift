import SwiftUI

@MainActor
@Observable
final class IslandPagesCoordinator {
    private(set) var isRefreshing = false
    var headerFocus: Int?
    let pages = IslandPage.allCases
    @ObservationIgnored private let day: IslandDayPage
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?

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
        page.content(day: day)
    }

    func didOpen(page: IslandPage) {
        headerFocus = nil
        cancelRefresh()
        if page == .day { day.reloadIfStale() }
        day.clock.start()
    }

    func didClose() {
        cancelRefresh()
        headerFocus = nil
        day.clock.stop()
    }

    func refresh(_ page: IslandPage) {
        cancelRefresh()
        let identity = UUID()
        refreshID = identity
        isRefreshing = true
        page.refresh(day: day)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled, self?.refreshID == identity else { return }
            guard let self else { return }
            guard !Task.isCancelled, refreshID == identity else { return }
            isRefreshing = false
            refreshTask = nil
            refreshID = nil
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        isRefreshing = false
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
