import Foundation

struct TreadmillTotals: Equatable, Sendable {
    var seconds = 0.0
    var meters = 0.0
    var kcal = 0.0
    var steps = 0.0
    var walks = 0

    var averageKmh: Double { seconds > 0 ? meters / 1000 / (seconds / 3600) : 0 }

    mutating func add(_ record: TreadmillRecord) {
        seconds += record.seconds
        meters += record.meters
        kcal += record.kcal
        steps += record.steps
        if record.imported != true { walks += 1 }
    }
}
