import Foundation
import Observation

@MainActor @Observable
final class TodoIslandFeed {
    enum Failure: Error { case unsupportedRecurrence, snapshotWrite }

    private(set) var snapshot: TodoIslandSnapshot
    private(set) var failure: Failure?
    private(set) var nextBoundary: Date?
    @ObservationIgnored private let store: TodoStore
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private weak var presenter: (any TodoIslandPresenting)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var session: UUID?

    init(store: TodoStore, fileURL: URL, calendar: Calendar,
         now: @escaping () -> Date, presenter: (any TodoIslandPresenting)? = nil) {
        self.store = store
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
        self.presenter = presenter
        snapshot = TodoIslandSnapshot(state: store.state, now: now(), calendar: calendar)
    }

    isolated deinit { timer?.invalidate() }

    func start() {
        guard session == nil else { return }
        session = UUID()
        track()
        refresh()
    }

    func stop() {
        session = nil
        timer?.invalidate()
        timer = nil
        nextBoundary = nil
    }

    func refresh() {
        let date = now()
        snapshot = TodoIslandSnapshot(state: store.state, now: date, calendar: calendar)
        do {
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
            failure = nil
        } catch {
            failure = .snapshotWrite
        }
        presenter?.update(snapshot)
        timer?.invalidate()
        guard let session else { return }
        let minute = calendar.dateInterval(of: .minute, for: date)?.end
        let day = calendar.dateInterval(of: .day, for: date)?.end
        nextBoundary = [minute, day].compactMap { $0 }.min()
        guard let nextBoundary else { return }
        let timer = Timer(timeInterval: max(0, nextBoundary.timeIntervalSince(date)),
                          repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.session == session else { return }
                self.refresh()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func complete(_ id: String) throws {
        let date = now()
        if var task = store.state.tasks[id], var due = task.due, let text = due.recurrenceRule {
            guard let rule = TodoDateParser.parse(text, now: date, calendar: calendar,
                                                 timeZone: calendar.timeZone,
                                                 preferredLanguage: .english)?.recurrence else {
                throw Failure.unsupportedRecurrence
            }
            let anchored = rule.anchored(to: due.date, calendar: calendar)
            due.recurrenceRule = anchored.canonicalString
            due.date = TodoRecurrence.nextDue(anchored, currentDue: due.date, hasTime: !due.isAllDay,
                                             completedAt: date, calendar: calendar)
            task.due = due
            task.completedAt = nil
            var commands: [TodoCommand] = [.updateTask(task)]
            var parents: Set<String> = [id]
            while true {
                let children = store.state.tasks.values.filter {
                    $0.parentID.map { parents.contains($0) } ?? false
                }
                guard !children.isEmpty else { break }
                commands += children.map { .uncompleteTask(id: $0.id) }
                parents = Set(children.map(\.id))
            }
            try store.perform(.batch(commands))
        } else {
            try store.perform(.completeTask(id: id, at: date))
        }
        refresh()
    }

    private func track() {
        guard let session else { return }
        withObservationTracking {
            _ = store.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.session == session else { return }
                self.track()
                self.refresh()
            }
        }
    }
}
