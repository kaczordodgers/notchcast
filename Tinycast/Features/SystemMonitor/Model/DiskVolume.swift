import Foundation

nonisolated struct DiskVolume: Sendable, Equatable {
    let name: String
    let mountPath: String
    let total: UInt64
    let available: UInt64
    var isReadOnly = false
    var isEjectable = false

    static func canEject(isLocal: Bool?, isInternal: Bool?, isRoot: Bool?,
                         isEjectable: Bool?) -> Bool {
        isLocal != false && isInternal != true && isRoot != true &&
            (isEjectable == true || isInternal == false)
    }

    func isLowSpace(thresholdPercent: Double = 10) -> Bool {
        guard total > 0, thresholdPercent.isFinite else { return false }
        return Double(available) / Double(total) * 100 < min(100, max(0, thresholdPercent))
    }
}
