import Foundation

struct TreadmillSample: Codable, Equatable, Sendable {
    var speed = 0.0
    var seconds = 0
    var meters = 0
    var kcal = 0.0
    var steps = 0

    var isValid: Bool {
        speed.isFinite && (0...25.5).contains(speed) && (0...65_535).contains(seconds)
            && (0...655_350).contains(meters) && kcal.isFinite && (0...6553.5).contains(kcal)
            && (0...65_535).contains(steps)
    }
}
