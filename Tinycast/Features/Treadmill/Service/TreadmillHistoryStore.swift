import Foundation
import Observation

@MainActor @Observable
final class TreadmillHistoryStore {
    private(set) var archive = TreadmillArchive()
    private(set) var isLoaded = false
    @ObservationIgnored private let repository: TreadmillRepository
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var savedRevision = -1
    @ObservationIgnored private var write: Task<Void, Error>?

    init(repository: TreadmillRepository) { self.repository = repository }

    func load() async throws {
        guard !isLoaded else { return }
        let loaded = try await repository.load()
        try Task.checkCancellation()
        guard !isLoaded else { return }
        archive = loaded
        isLoaded = true
        revision += 1
    }

    func update(current: TreadmillWalk?, finished: [TreadmillRecord]) {
        guard isLoaded else { return }
        let previousCurrent = archive.current
        let previousCount = archive.records.count
        archive.apply(current: current, finished: finished)
        guard archive.current != previousCurrent || archive.records.count != previousCount else { return }
        revision += 1
    }

    func markLubricated(odometerKm: Double) {
        guard isLoaded, odometerKm.isFinite, (0...253_402_300_799).contains(odometerKm) else { return }
        archive.lubricatedKm = odometerKm
        revision += 1
    }

    func takeGoalReached(_ goal: TreadmillGoal?, now: Date, calendar: Calendar) -> Bool {
        guard isLoaded, let goal else { return false }
        let day = calendar.startOfDay(for: now)
        guard archive.goalAnnouncedDay != day,
              goal.progress(summary(now: now, calendar: calendar).today) >= 1 else { return false }
        archive.goalAnnouncedDay = day
        revision += 1
        return true
    }

    func summary(now: Date, calendar: Calendar) -> TreadmillSummary {
        TreadmillSummary(records: archive.records, current: archive.current, now: now, calendar: calendar)
    }

    func flush() async throws {
        guard isLoaded else { return }
        while savedRevision != revision {
            if let write {
                try await write.value
                continue
            }
            let snapshot = archive
            let token = revision
            let repository = repository
            let task = Task {
                do {
                    try await repository.save(snapshot)
                    savedRevision = token
                    write = nil
                } catch {
                    write = nil
                    throw error
                }
            }
            write = task
            try await task.value
        }
    }
}
