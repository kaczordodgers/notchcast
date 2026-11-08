import Foundation

struct TreadmillArchive: Codable, Equatable, Sendable {
    var records: [TreadmillRecord] = []
    var current: TreadmillWalk?
    var lubricatedKm = 0.0
    var goalAnnouncedDay: Date?

    var isValid: Bool {
        records.allSatisfy(\.isValid) && (current?.isValid ?? true)
            && lubricatedKm.isFinite && (0...253_402_300_799).contains(lubricatedKm)
    }

    func lubeDueMark(odometerKm: Double) -> Double? {
        guard odometerKm.isFinite, odometerKm >= 200 else { return nil }
        let mark = floor(odometerKm / 200) * 200
        return mark > lubricatedKm ? mark : nil
    }

    mutating func apply(current: TreadmillWalk?, finished: [TreadmillRecord]) {
        self.current = current
        var known = Set(records.map(\.started))
        records.append(contentsOf: finished.filter { $0.isValid && known.insert($0.started).inserted })
    }
}
