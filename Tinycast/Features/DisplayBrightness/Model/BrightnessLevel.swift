import Foundation

struct BrightnessLevel: Equatable, Sendable {
    static let step = 1.0 / 16
    static let extraDimmingRange = 0.25
    static let minimumPicture = 0.05

    let value: Double
    let softwareOnly: Bool

    init(_ value: Double, softwareOnly: Bool = false) {
        let minimum = softwareOnly ? 0 : -Self.extraDimmingRange
        self.value = value.isNaN ? 0 : min(max(value, minimum), 1)
        self.softwareOnly = softwareOnly
    }

    var hardware: Double { max(value, 0) }
    var isDimmed: Bool { picture < 1 }

    var picture: Double {
        let position = softwareOnly ? value : 1 + min(value, 0) / Self.extraDimmingRange
        return Self.minimumPicture + (1 - Self.minimumPicture) * position
    }

    func refreshed(hardware: Double) -> Self {
        Self(hardware == 0 ? min(value, 0) : hardware)
    }

    func stepped(up: Bool, fine: Bool) -> Self {
        let delta = Self.step / (fine ? 4 : 1)
        let grid = value / delta
        let next = up ? floor(grid + 0.000001) + 1 : ceil(grid - 0.000001) - 1
        return Self(next * delta, softwareOnly: softwareOnly)
    }
}
