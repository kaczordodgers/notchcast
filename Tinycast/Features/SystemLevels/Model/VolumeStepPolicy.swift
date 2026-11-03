import Foundation

enum VolumeStepPolicy {
    static let tolerance = 0.0001

    static func candidates(from volume: Double, increasing: Bool, fine: Bool) -> [Double] {
        guard volume.isFinite, (0...1).contains(volume) else { return [] }
        let divisions = fine ? 64 : 16
        let current = Int((volume * Double(divisions)).rounded())
        let indexes = increasing ? Array((min(divisions, current + 1))...divisions)
            : Array((0...max(0, current - 1)).reversed())
        let limit = fine ? 4 : 2
        return indexes.prefix(limit).map { Double($0) / Double(divisions) }
    }

    static func advanced(from initial: Double, to actual: Double, increasing: Bool) -> Bool {
        guard actual.isFinite, (0...1).contains(actual) else { return false }
        return increasing ? actual > initial + tolerance : actual < initial - tolerance
    }
}
