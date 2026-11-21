import AppKit
import Observation

/// Renders levels, notices, status and the meeting expansion on the island.
@MainActor
final class IslandPresenter: IslandPresenting {
    private var dwell = IslandLevelDwell()
    private var dwellTask: Task<Void, Never>?
    private weak var pill: IslandController?
    private var band: HUDPanel?
    private var bandShown = false
    private var observing = false
    private var expansion = IslandMeetingExpansion()
    private var expansionTask: Task<Void, Never>?
    private var occurrence: IslandMeetingExpansion.Occurrence?
    private weak var expandedPill: IslandController?
    private var notices = IslandNoticeQueue()
    private var noticeTask: Task<Void, Never>?
    private var noticeDisplays: [String: UInt32] = [:]
    private weak var awayHost: IslandController?
    private var statuses: [IslandStatus] = []
    private var hovered = false
    private var noticeTaps: [String: @MainActor () -> Void] = [:]
    private var statusTaps: [String: @MainActor () -> Void] = [:]
    private(set) var menus: [Menu] = []
    let pages = IslandPageHost()
    private var song: IslandNowPlaying?
    private var songChange = IslandSongChange()
    private var songTask: Task<Void, Never>?
    private let keyHold = IslandKeyHold()
    private let now: @MainActor () -> TimeInterval
    private let sleep: @MainActor (TimeInterval) async throws -> Void

    /// A harness injects its own clock, so a dwell is checked exactly rather than against the wall.
    init(now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.now = now
        self.sleep = sleep
    }

    struct Menu {
        let owner: String
        let rows: [IslandMenuRow]
        let onSelect: @MainActor (String) -> Void
    }

    func showLevel(_ level: IslandLevel) {
        if dwell.show(level, at: now()) {
            dwellTask?.cancel()
            dwellTask = endWhenDwelled(dwell.presentation)
            if !observing { observePlacement() }
        }
        place()
        noticesChanged()
    }

    /// The carded meeting the resting glance shows, or nil; a hovered status name gives way to it.
    func meetingChanged(_ occurrence: IslandMeetingExpansion.Occurrence?) {
        self.occurrence = occurrence
        if occurrence != nil, !observing { observePlacement() }
        noticesChanged()
    }

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        notices.post(notice, at: now())
        noticeTaps[notice.id] = onTap
        if !observing { observePlacement() }
        noticesChanged()
    }

    func place(notice id: String, on display: UInt32?) {
        guard noticeDisplays[id] != display else { return }
        noticeDisplays[id] = display
        if notices.holds(id) { noticesChanged() }
        if keyHold.lease.owner == id { keyHold.move(near: host(for: id)?.screenShape) }
    }

    func holdKeys(for notice: String, onFocus: @escaping @MainActor (Bool) -> Void,
                  onKey: @escaping @MainActor (IslandHeldKey) -> Void) {
        keyHold.hold(near: host(for: notice)?.screenShape, during: notice, onFocus: onFocus, onKey: onKey)
    }

    func releaseKeys() { keyHold.release() }

    func end(notice id: String) {
        notices.end(id, at: now())
        noticeTaps[id] = nil
        noticeDisplays[id] = nil
        noticesChanged()
    }

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        statuses.removeAll { $0.id == id }
        statusTaps[id] = status == nil ? nil : onTap
        if let status { statuses.append(status) }
        AppCore.shared.island.resting?.statuses = statuses
        if hoverOpensPill { showNotices() }
        showOnPages()
    }

    /// A click on the resting pill opens the pages while any exist, else acts on what the pill shows.
    var tap: (@MainActor () -> Void)? {
        pages.deck.opensOnClick ? nil : tap(for: restingNotice)
    }

    /// What the pill shows heads the open page, its tap that row's click, so no page hides it (#1005).
    private func showOnPages() {
        pages.show(IslandHover.notice(top: notices.notice, statuses: statuses,
                                      glance: AppCore.shared.island.resting?.glance != nil, level: false, hovered: true),
                   onTap: tap(for: notices.notice))
    }

    /// The shown notice's tap, else none under the meeting glance, else the last status's.
    private func tap(for notice: IslandNotice?) -> (@MainActor () -> Void)? {
        if let notice { return noticeTaps[notice.id] }
        if AppCore.shared.island.resting?.glance != nil { return nil }
        return statuses.last.flatMap { statusTaps[$0.id] }
    }

    /// The pointer resting on the island opens the long form of what it shows (#884 H2 to H7).
    func hoverChanged(_ open: Bool) {
        hovered = open
        hoverPages(open)
        noticesChanged()
    }

    private func hoverPages(_ open: Bool) {
        let resting = AppCore.shared.island.resting
        pages.hover(open, on: resting, glance: resting?.glance != nil)
    }

    /// Pages take the hover first (#975); with none, the pill's own long form shows as before.
    private var hoverOpensPill: Bool { hovered && !pages.isOpen }

    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        pages.set(page, id: id, onAction: onAction)
        if hovered { hoverChanged(true) }
    }

    func watchPages(id: String, onChange: (@MainActor (_ visible: Bool) -> Void)?) {
        pages.watch(id: id, onChange: onChange)
    }

    func showPage(id: String) { pages.showPage(id: id) }

    /// The glance draws no running time, so a position sync alone never redraws the pill.
    func setSong(_ next: IslandNowPlaying?) {
        var still = next
        still?.time = nil
        guard still != song else { return }
        song = still
        let resting = AppCore.shared.island.resting
        resting?.song = song
        if songChange.update(song, notch: resting?.notchWidth != nil), songQuiet {
            songTask?.cancel()
            songTask = Task { [weak self, sleep, seconds = songChange.seconds] in
                try? await sleep(seconds)
                guard !Task.isCancelled, let self else { return }
                self.songChange.cut()
                AppCore.shared.island.resting?.songChange = false
            }
        } else if !songQuiet {
            songChange.cut()
        }
        resting?.songChange = songChange.shown != nil
    }

    /// A meeting, a level, a notice or the open island outranks the song change and cuts it (D7, D16).
    private var songQuiet: Bool {
        AppCore.shared.island.resting?.glance == nil && restingNotice == nil && dwell.level == nil && !pages.isOpen
            && expansion.showing == nil
    }

    private func cutSongChange() {
        guard songChange.shown != nil, !songQuiet else { return }
        songChange.cut()
        songTask?.cancel()
        AppCore.shared.island.resting?.songChange = false
    }

    private func placedHost(for id: String) -> IslandController? {
        noticeDisplays[id].flatMap { AppCore.shared.island.controller(on: $0) }
    }

    private func host(for id: String) -> IslandController? {
        placedHost(for: id) ?? AppCore.shared.island.resting
    }

    private var restingNotice: IslandNotice? {
        guard let notice = notices.notice else { return nil }
        if let placed = placedHost(for: notice.id), placed !== AppCore.shared.island.resting { return nil }
        return notice
    }

    private func showNotices() {
        let resting = AppCore.shared.island.resting
        let placed = notices.notice.flatMap { placedHost(for: $0.id) }
        let away = placed === resting ? nil : placed
        if awayHost !== away { awayHost?.notice = nil }
        awayHost = away
        away?.notice = notices.notice
        resting?.notice = IslandHover.notice(top: away == nil ? notices.notice : nil, statuses: statuses,
                                             glance: resting?.glance != nil, level: dwell.level != nil,
                                             hovered: hoverOpensPill)
    }

    /// Restores content without reposting, so none re-announces.
    func restore(_ controller: IslandController, resting: Bool) {
        let placed = notices.notice.flatMap { placedHost(for: $0.id) }
        if placed !== controller { controller.notice = resting && placed == nil ? notices.notice : nil }
        controller.statuses = resting ? statuses : []
        controller.song = resting ? song : nil
        controller.songChange = resting && songChange.shown != nil
    }

    /// A look change repaints a band already up, which would otherwise keep the old look to its fade.
    func looksChanged() {
        guard bandShown else { return }
        (band?.contentView as? IslandLevelBand)?.restyle(frosted: AppCore.shared.island.frosted(on: nil))
    }

    /// A rebuild can add or drop the resting pill, which a notice's dwell waits for.
    func restingChanged() {
        if hovered { hoverPages(true) }
        noticesChanged()
        if let id = keyHold.lease.owner { keyHold.move(near: host(for: id)?.screenShape) }
    }

    /// An owner keeps its first registration's place, so replacing its rows never reorders the menu.
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        let index = menus.firstIndex { $0.owner == owner }
        switch (index, rows.isEmpty) {
        case (let index?, true): menus.remove(at: index)
        case (let index?, false): menus[index] = Menu(owner: owner, rows: rows, onSelect: onSelect)
        case (nil, false): menus.append(Menu(owner: owner, rows: rows, onSelect: onSelect))
        case (nil, true): return
        }
        AppCore.shared.island.pillMenu.refit(keepingSelection: true)
    }

    #if DEBUG
    var presentations: Int { dwell.presentation }
    var expansions: Int { expansion.presentation }
    /// A scene's shorter expansion, so it settles inside the 9 s run.
    func previewExpansion(seconds: TimeInterval) { expansion = IslandMeetingExpansion(seconds: seconds) }
    #endif

    /// Anything that keeps the pill's notice unseen pauses its dwell; the announcement follows the top.
    private func noticesChanged() {
        let time = now()
        let core = AppCore.shared
        let host = notices.notice.flatMap { host(for: $0.id) } ?? core.island.resting
        let unseen = dwell.level != nil || core.palette.isVisible || core.isShowingDialog || host == nil
        let held = unseen || hovered && restingNotice != nil
        if notices.paused != held { notices.pause(held, at: time) }
        showNotices()
        showOnPages()
        if let text = notices.announcement() {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            #if DEBUG
            IslandVerification.announcements.append(text)
            #endif
        }
        updateExpansion()
        cutSongChange()
        noticeTask?.cancel()
        noticeTask = notices.remaining(at: time).map(expireWhenDwelled)
        keyHold.noticesChanged { notices.holds($0) }
    }

    private func expireWhenDwelled(_ left: TimeInterval) -> Task<Void, Never> {
        Task { [weak self, now, sleep] in
            try? await sleep(left)
            guard !Task.isCancelled, let self else { return }
            let gone = self.notices.notice?.id
            self.notices.expire(at: now())
            if let gone, self.notices.notice?.id != gone {
                self.noticeTaps[gone] = nil
                self.noticeDisplays[gone] = nil
            }
            self.noticesChanged()
        }
    }

    /// Sleeps out the dwell, then again for whatever repeats added, so a burst never restarts it.
    private func endWhenDwelled(_ token: Int) -> Task<Void, Never> {
        Task { [weak self, now, sleep] in
            while let left = self?.dwell.remaining(token, at: now()) {
                try? await sleep(left)
                guard !Task.isCancelled else { return }
            }
            guard let self, self.dwell.presentation == token, self.dwell.level == nil else { return }
            self.place()
            self.dwellTask = nil
            self.noticesChanged()
        }
    }

    private func settleWhenExpanded(_ token: Int) -> Task<Void, Never> {
        Task { [weak self, now, sleep] in
            while let left = self?.expansion.remaining(token, at: now()) {
                try? await sleep(left)
                guard !Task.isCancelled else { return }
            }
            guard let self, self.expansion.presentation == token else { return }
            self.expansionTask = nil
            self.updateExpansion()
        }
    }

    private func updateExpansion() {
        let core = AppCore.shared
        if expansion.update(carded: occurrence, waiting: dwell.level != nil || restingNotice != nil,
                            covered: core.palette.isVisible || core.isShowingDialog, at: now()) {
            expansionTask?.cancel()
            expansionTask = settleWhenExpanded(expansion.presentation)
        }
        if expansion.showing == nil {
            expansionTask?.cancel()
            expansionTask = nil
        }
        let pill = expansion.showing == nil && !hoverOpensPill ? nil : core.island.resting
        if expandedPill !== pill { expandedPill?.expanded = false }
        expandedPill = pill
        pill?.expanded = true
    }

    private func place() {
        let core = AppCore.shared
        let placement = dwell.placement(palette: core.palette.isVisible, question: core.isShowingDialog)
        if placement != .band { dismissBand() }
        if placement != .pill { pill?.level = nil }
        switch (placement, dwell.level) {
        case (.band?, let level?):
            stack(IslandLevelArt(level, notch: false, frosted: core.island.frosted(on: nil)))
        case (.pill?, let level?):
            pill = core.island.resting
            pill?.level = level
        default:
            pill = nil
        }
    }

    /// The palette or a question can open mid-dwell, and the level must follow without restarting.
    private func observePlacement() {
        observing = true
        withObservationTracking {
            _ = AppCore.shared.palette.isVisible
            _ = AppCore.shared.isShowingDialog
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observing = false
                guard self.dwell.level != nil || self.occurrence != nil || self.notices.notice != nil else { return }
                self.observePlacement()
                self.place()
                self.noticesChanged()
            }
        }
    }

    private func stack(_ art: IslandLevelArt) {
        let band = band ?? makeBand(art.bandSize)
        (band.contentView as? IslandLevelBand)?.art = art
        guard !bandShown else { return }
        bandShown = true
        AppCore.shared.island.overlays.placeReport(band, screen: nil)
        if band.isVisible {
            band.cancelFade()
        } else {
            band.fadeIn(duration: Theme.Duration.enter) { band.orderFrontRegardless() }
        }
    }

    private func makeBand(_ size: CGSize) -> HUDPanel {
        let band = HUDPanel()
        band.setContentSize(size)
        band.contentView = IslandLevelBand(frame: CGRect(origin: .zero, size: size))
        self.band = band
        return band
    }

    private func dismissBand() {
        guard bandShown, let band else { return }
        bandShown = false
        band.fadeOut(duration: Theme.Duration.exit)
    }

    isolated deinit {
        dwellTask?.cancel()
        expansionTask?.cancel()
        noticeTask?.cancel()
        songTask?.cancel()
    }
}
