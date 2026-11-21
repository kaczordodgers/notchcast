import Foundation

/// Warns once when free space falls below the threshold; rising a margin above it re-arms the warning.
struct LowDiskPolicy: Equatable, Sendable {
    static let defaultThresholdGB = 10
    static let thresholdRange = 1...500
    static let checkInterval: Duration = .seconds(30 * 60)
    static let thresholdKey = "lowDiskThresholdGB"
    static let warnedKey = "lowDiskWarned"
    static let statusID = "lowDisk"
    static let symbol = "internaldrive"

    var hasWarned = false

    var status: IslandStatus? {
        guard hasWarned else { return nil }
        return IslandStatus(
            id: Self.statusID, symbol: Self.symbol, text: nil,
            label: String(localized: "Low disk space", table: "NotchcastLowDisk"), tone: nil)
    }

    /// An unset or out-of-range stored value falls back to the default or the nearest bound.
    static func thresholdGB(stored: Int?) -> Int {
        guard let stored else { return defaultThresholdGB }
        return min(max(stored, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// Decimal gigabytes, as Finder and `ByteCountFormatter` count them.
    static func bytes(gigabytes: Int) -> Int64 { Int64(gigabytes) * 1_000_000_000 }

    /// Purgeable space swings by gigabytes, so re-arming sits a tenth of the threshold (at least 1 GB) above it.
    static func rearmBytes(thresholdGB: Int) -> Int64 {
        let threshold = bytes(gigabytes: thresholdGB)
        return threshold + max(bytes(gigabytes: 1), threshold / 10)
    }

    /// True for the one reading that should warn; a negative reading or a sleeping display changes nothing.
    mutating func shouldWarn(free: Int64, thresholdGB: Int, displayAsleep: Bool) -> Bool {
        guard free >= 0, !displayAsleep else { return false }
        guard free < Self.bytes(gigabytes: thresholdGB) else {
            if free >= Self.rearmBytes(thresholdGB: thresholdGB) { hasWarned = false }
            return false
        }
        defer { hasWarned = true }
        return !hasWarned
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static func warning(free: Int64) -> String {
        String(localized: "Low disk space: \(size(free))", table: "NotchcastLowDisk")
    }

    static func available(free: Int64) -> String {
        String(localized: "\(size(free)) free", table: "NotchcastLowDisk")
    }
}
