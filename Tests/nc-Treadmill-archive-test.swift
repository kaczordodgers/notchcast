// notchcast-sources: Tinycast/Features/Treadmill/Model/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/Service/TreadmillRepository.swift
import Foundation

@main
struct TreadmillArchiveTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "treadmill-archive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = TreadmillRecord(started: 1_700_000_000, ended: 1_700_000_600,
            seconds: 600, meters: 800, kcal: 40, steps: 900, averageKmh: 4.8, imported: true)
        let synthetic = TreadmillArchive(records: [record], lubricatedKm: 200)
        let fixture = root.appending(path: "fixture.json")
        try JSONEncoder().encode(synthetic).write(to: fixture)
        for input in [fixture] + CommandLine.arguments.dropFirst().map({ URL(fileURLWithPath: $0) }) {
            try await verify(input, root: root)
        }
        let empty = try await TreadmillRepository(directory: root.appending(path: "missing")).load()
        precondition(empty == TreadmillArchive(), "A missing archive must not create personal history")
        print("Treadmill archive preservation passed")
    }

    private static func verify(_ input: URL, root: URL) async throws {
        let original = try Data(contentsOf: input)
        let before = try JSONDecoder().decode(TreadmillArchive.self, from: original)
        let directory = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = directory.appending(path: "treadmill.json")
        try original.write(to: copy)
        let repository = TreadmillRepository(directory: directory)
        let after = try await repository.load()
        precondition(before == after, "Loading preserves every record and recovery field")
        let unchanged = try Data(contentsOf: copy)
        precondition(unchanged == original, "Loading does not write to the archive")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: (before.records.map(\.started).max() ?? 0) + 1)
        let interval = calendar.dateInterval(of: .year, for: now)!
        var total = TreadmillTotals()
        var year = TreadmillTotals()
        for record in before.records {
            total.add(record)
            if interval.contains(Date(timeIntervalSince1970: record.started)) { year.add(record) }
        }
        let summary = TreadmillSummary(records: after.records, current: nil, now: now, calendar: calendar)
        precondition(abs(summary.odometerKm * 1000 - total.meters) < 0.001, "Odometer preserves stored distance")
        precondition(summary.year == year, "Computed year totals preserve stored counters and walk count")
        try await repository.save(after)
        let reloaded = try await repository.load()
        precondition(reloaded == before, "Saving and reloading preserve the snapshot")
        print("\(input.lastPathComponent): records \(before.records.count) == \(after.records.count), "
            + "seconds \(total.seconds) == \(summary.year.seconds), meters \(total.meters) == \(summary.year.meters), "
            + "kcal \(total.kcal) == \(summary.year.kcal), steps \(total.steps) == \(summary.year.steps)")
    }
}
