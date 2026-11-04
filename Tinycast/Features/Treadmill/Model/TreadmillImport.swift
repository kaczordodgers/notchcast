import Foundation

enum TreadmillImport {
    static func phoneTotals(calendar: Calendar) -> [TreadmillRecord] {
        let blocks: [(month: Int, day: Int, minutes: Double, km: Double, kcal: Double, steps: Double)] = [
            (8, 15, 5957, 395.69, 20622, 590_386),
            (9, 10, 1433, 95.42, 4974, 139_615),
            (9, 24, 280, 18.6, 970, 27_525),
        ]
        return blocks.compactMap { block in
            guard let date = calendar.date(from: DateComponents(year: 2026, month: block.month, day: block.day, hour: 12))
            else { return nil }
            return TreadmillRecord(started: date.timeIntervalSince1970,
                                   ended: date.timeIntervalSince1970 + block.minutes * 60,
                                   seconds: block.minutes * 60, meters: (block.km * 1000).rounded(),
                                   kcal: block.kcal, steps: block.steps, averageKmh: 0, imported: true)
        }
    }

    static func merge(_ incoming: [TreadmillRecord], into existing: [TreadmillRecord], calendar: Calendar)
        -> [TreadmillRecord] {
        var result = existing
        var known = Set(existing.map(\.started))
        for record in incoming + phoneTotals(calendar: calendar) where record.isValid {
            if record.imported == true, result.contains(where: {
                $0.imported == true && $0.seconds == record.seconds && $0.meters == record.meters && $0.steps == record.steps
            }) { continue }
            if known.insert(record.started).inserted { result.append(record) }
        }
        return result.sorted { $0.started < $1.started }
    }
}
