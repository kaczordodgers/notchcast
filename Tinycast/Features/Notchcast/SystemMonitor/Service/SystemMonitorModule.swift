import Foundation

/// Samples the Mac while the System page or the hot check needs it, posts the page and the hot glyph (#977).
@MainActor
final class SystemMonitorModule: NotchcastModule {
    private let context: NotchcastContext
    private let system: MonitorSystem
    private let locale: Locale
    private var board = MonitorBoard()
    private var isOn = false
    private var shows = false
    private var posted: IslandPage?
    private var status: IslandStatus?
    private(set) var ejectTasks: [String: Task<Void, Never>] = [:]
    private(set) var loop: Task<Void, Never>?

    init(context: NotchcastContext, system: MonitorSystem, locale: Locale = .autoupdatingCurrent) {
        self.context = context
        self.system = system
        self.locale = locale
    }

    func start() {
        guard !isOn else { return }
        isOn = true
        post()
        context.presenter.watchPages(id: MonitorPage.id) { [weak self] in self?.setVisible($0) }
        run()
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        context.presenter.watchPages(id: MonitorPage.id, onChange: nil)
        loop?.cancel()
        loop = nil
        for task in ejectTasks.values { task.cancel() }
        ejectTasks.removeAll()
        board = MonitorBoard()
        shows = false
        posted = nil
        if status != nil {
            status = nil
            context.presenter.setStatus(nil, for: MonitorPage.id, onTap: nil)
        }
        context.presenter.setPage(nil, id: MonitorPage.id, onAction: nil)
    }

    private func setVisible(_ visible: Bool) {
        guard isOn, visible != shows else { return }
        shows = visible
        run()
    }

    /// One loop at a time: a new one reads at once, so showing the page or Command-R never waits out a nap.
    private func run() {
        loop?.cancel()
        let system = system
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let (detail, previous) = self.map({ ($0.shows, $0.shows ? $0.board.processTimes : [:]) }) else { return }
                let reading = await system.read(detail, previous)
                guard !Task.isCancelled, let interval = self?.apply(reading) else { return }
                do { try await system.sleep(interval) } catch { return }
            }
        }
    }

    /// Records the read and says how long to wait for the next one; nil once the switch is off.
    private func apply(_ reading: MonitorReading) -> Duration? {
        guard isOn else { return nil }
        board.apply(reading, processorCount: system.processorCount, locale: locale)
        let next = MonitorPage.status(board.heat)
        if next != status {
            status = next
            context.presenter.setStatus(next, for: MonitorPage.id) { [weak self] in
                self?.context.presenter.showPage(id: MonitorPage.id)
            }
        }
        if shows { post() }
        return board.interval(shown: shows)
    }

    private func post() {
        let page = MonitorPage.page(board, locale: locale)
        // The island redraws on every post, so an unchanged page is not sent again.
        guard page != posted else { return }
        posted = page
        context.presenter.setPage(page, id: MonitorPage.id) { [weak self] action in
            self?.onAction(action)
        }
    }

    private func onAction(_ action: String) {
        guard isOn else { return }
        if action == IslandPage.refreshAction {
            run()
            return
        }
        guard shows, let path = MonitorVolumes.path(for: action), ejectTasks[path] == nil,
              let volume = board.sample.volumes.prefix(MonitorVolumes.rowLimit).first(where: { $0.path == path })
        else { return }

        let eject = system.eject
        board.ejecting.insert(path)
        ejectTasks[path] = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let result = await eject(path)
            guard !Task.isCancelled else { return }
            self?.finishEject(volume, outcome: result.outcome)
        }
        post()
    }

    private func finishEject(_ volume: MonitorVolume, outcome: MonitorEjectOutcome) {
        ejectTasks[volume.path] = nil
        board.ejecting.remove(volume.path)
        if outcome == .ejected { board.didEject(volume.path) }
        context.presenter.post(MonitorPage.ejectNotice(outcome, volume: volume), onTap: nil)
        if shows { post() }
        if outcome == .ejected { run() }
    }
}
