// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandPage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandPageRefresh.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandInputState.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
import Foundation

@main
struct IslandPagesTests {
    @MainActor static func main() async {
        await refresh()
        pages()
        dismissal()
        hover()
        preferences()
        print("notchcast-island-pages: registry, landing, pin, hover and preferences passed")
    }

    @MainActor static func refresh() async {
        var homeReloads = 0
        var dayReloads = 0
        await IslandPage.home.refresh(home: { homeReloads += 1 }, day: { dayReloads += 1 }, usage: {})
        expect(homeReloads == 1 && dayReloads == 0, "Home refreshes its activity content")
        await IslandPage.day.refresh(home: { homeReloads += 1 }, day: { dayReloads += 1 }, usage: {})
        expect(homeReloads == 1 && dayReloads == 1, "Day refreshes its calendar data")
        var usageReloads = 0
        await IslandPage.usage.refresh(home: { homeReloads += 1 }, day: { dayReloads += 1 }, usage: { usageReloads += 1 })
        expect(usageReloads == 1 && homeReloads == 1 && dayReloads == 1, "AI usage refreshes its quotas")
        let refresh = IslandPageRefresh()
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        refresh.run { await withCheckedContinuation { first = $0 } }
        expect(refresh.isRefreshing, "refresh starts immediately")
        while first == nil { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        expect(refresh.isRefreshing, "spinner waits for real work")
        refresh.run { await withCheckedContinuation { second = $0 } }
        while second == nil { await Task.yield() }
        first?.resume()
        for _ in 0..<20 { await Task.yield() }
        expect(refresh.isRefreshing, "stale completion cannot clear replacement refresh")
        second?.resume()
        while refresh.isRefreshing { await Task.yield() }
        refresh.run { await Task.yield() }
        refresh.cancel()
        expect(!refresh.isRefreshing, "closing clears refresh immediately")
        await Task.yield()
    }

    static func pages() {
        expect(IslandPage.allCases == [.home, .day, .usage], "page order follows the registry")
        expect(IslandPage.allCases.map(\.key) == ["1", "2", "3"], "page shortcuts follow order")
        for page in IslandPage.allCases {
            expect(IslandPage.page(forKey: page.key) == page, "page key round-trips")
            expect(!page.symbol.isEmpty, "each registered page has a glyph")
        }
        for key in ["0", "4", "p", "", "-1"] {
            expect(IslandPage.page(forKey: key) == nil, "unregistered page key is ignored")
        }
        expect(IslandPage.home.landingPage(hasLiveActivities: false) == .day,
               "an idle opening lands on Day")
        expect(IslandPage.home.landingPage(hasLiveActivities: true) == .home,
               "live activities keep Home as the landing page")
        expect(IslandPage.day.landingPage(hasLiveActivities: true) == .day,
               "an explicit Day opening keeps Day")
    }

    static func dismissal() {
        let passive: [IslandInputState.Dismissal] = [.outsideClick, .appSwitch, .mouseOut]
        for reason in passive {
            var state = IslandInputState()
            state.open()
            state.dismiss(reason)
            expect(!state.isOpen, "an unpinned island dismisses on \(reason)")
            state.open()
            state.togglePin()
            state.dismiss(reason)
            expect(state.isOpen && state.isPinned, "a pinned island survives \(reason)")
        }
        for reason in [IslandInputState.Dismissal.escape, .pageKey] {
            var state = IslandInputState()
            state.open()
            state.togglePin()
            state.dismiss(reason)
            expect(!state.isOpen && !state.isPinned, "\(reason) always closes and unpins")
        }
        var state = IslandInputState()
        state.togglePin()
        expect(!state.isOpen && !state.isPinned, "a hidden island cannot be pinned")
        state.open()
        state.togglePin()
        state.togglePin()
        expect(!state.isOpen && !state.isPinned, "the second pin command closes and unpins")
        state.open()
        state.setPinned(true)
        state.close()
        expect(!state.isPinned, "module teardown clears pin state")
    }

    static func hover() {
        var clock: TimeInterval = 100
        for delay in [0.1, 0.3, 0.5, 1.0] {
            var state = IslandInputState()
            state.pointer(inside: true, now: clock, hoverEnabled: true, delay: delay)
            let deadline = clock + delay
            expect(state.advance(now: deadline - 0.001) == nil, "hover waits the whole delay")
            expect(!state.isOpen, "hover does not open early")
            expect(state.advance(now: deadline) == .open && state.isOpen, "hover opens at its deadline")
            expect(state.advance(now: deadline + 10) == nil, "a deadline fires only once")
            clock += 10
        }
        var state = IslandInputState()
        state.pointer(inside: true, now: clock, hoverEnabled: true, delay: 0.3)
        state.pointer(inside: true, now: clock + 0.2, hoverEnabled: true, delay: 0.3)
        expect(state.pendingHover?.deadline == clock + 0.3, "pointer movement does not restart resting")
        state.pointer(inside: false, now: clock + 0.25, hoverEnabled: true, delay: 0.3)
        expect(state.advance(now: clock + 1) == nil && !state.isOpen, "leaving cancels hover open")
        state.pointer(inside: true, now: clock + 2, hoverEnabled: false, delay: 0.3)
        expect(state.advance(now: clock + 3) == nil, "the hover switch gates opening")
        state.pointer(inside: false, now: clock + 4, hoverEnabled: true, delay: 0.3)
        state.pointer(inside: true, now: clock + 5, hoverEnabled: true, delay: 0.3)
        state.cancelHoverOpen()
        expect(state.advance(now: clock + 6) == nil, "disabling hover cancels an outstanding opening")
        state.open()
        state.pointer(inside: false, now: clock + 7, hoverEnabled: true, delay: 1)
        expect(state.advance(now: clock + 7.299) == nil, "mouse-out uses its own close delay")
        state.pointer(inside: true, now: clock + 7.299, hoverEnabled: true, delay: 1)
        expect(state.advance(now: clock + 8) == nil && state.isOpen, "returning cancels mouse-out")
        state.pointer(inside: false, now: clock + 9, hoverEnabled: true, delay: 1)
        state.togglePin()
        expect(state.advance(now: clock + 10) == nil && state.isOpen, "pin cancels pending mouse-out")
        state.close()
        state.open()
        state.pointer(inside: true, now: clock + 11, hoverEnabled: true, delay: 0.3)
        state.pointer(inside: false, now: clock + 12, hoverEnabled: true, delay: 0.3)
        expect(state.advance(now: clock + 12.3) == .close && !state.isOpen,
               "mouse-out closes an unpinned island at its deadline")
        state.open()
        state.pointer(inside: true, now: clock + 13, hoverEnabled: true, delay: 0.3)
        state.pointer(inside: false, now: clock + 14, hoverEnabled: true, delay: 0.3)
        expect(state.advance(now: clock + 15, focused: true) == nil && state.isOpen,
               "mouse-out preserves a focused island")
        state.dismiss(.mouseOut, focused: true)
        expect(state.isOpen, "direct mouse-out dismissal preserves focus")
    }

    @MainActor static func preferences() {
        let suite = "app.notchcast.tests.pages.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        expect(preferences.islandHoverDelay == .standard, "absent hover delay defaults to 0.3 seconds")
        expect(NotchcastPreferences.HoverDelay.allCases.map(\.rawValue) == [0.1, 0.3, 0.5, 1],
               "the typed preference offers exactly the design's four delays")
        for delay in NotchcastPreferences.HoverDelay.allCases {
            preferences.islandHoverDelay = delay
            expect(NotchcastPreferences(suiteName: suite).islandHoverDelay == delay,
                   "every hover delay persists in the isolated preference suite")
            expect(!delay.title.isEmpty, "every delay has a locale-formatted title")
        }
        defaults.set(9, forKey: "islandHoverDelay")
        expect(NotchcastPreferences(suiteName: suite).islandHoverDelay == .standard,
               "an invalid stored delay restores the default")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
