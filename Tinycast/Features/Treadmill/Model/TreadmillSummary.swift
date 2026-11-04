import Foundation

struct TreadmillSummary: Sendable {
    struct Day: Sendable {
        let date: Date
        var totals = TreadmillTotals()
    }

    var today = TreadmillTotals()
    var week = TreadmillTotals()
    var month = TreadmillTotals()
    var year = TreadmillTotals()
    var odometerKm = 0.0
    var monthDays: [Day] = []

    init(records: [TreadmillRecord], current: TreadmillWalk?, now: Date, calendar: Calendar) {
        if let interval = calendar.dateInterval(of: .month, for: now),
           let days = calendar.range(of: .day, in: .month, for: now) {
            monthDays = days.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: interval.start).map { Day(date: $0) }
            }
        }
        let intervals = [Calendar.Component.day, .weekOfYear, .month, .year].map {
            calendar.dateInterval(of: $0, for: now)
        }
        for record in records + (current.map { [$0.record] } ?? []) where record.isValid {
            let date = Date(timeIntervalSince1970: record.started)
            guard date <= now else { continue }
            odometerKm += record.meters / 1000
            if intervals[0]?.contains(date) == true { today.add(record) }
            if intervals[1]?.contains(date) == true { week.add(record) }
            if intervals[2]?.contains(date) == true {
                month.add(record)
                if record.imported != true,
                   let index = monthDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                    monthDays[index].totals.add(record)
                }
            }
            if intervals[3]?.contains(date) == true { year.add(record) }
        }
    }
}
