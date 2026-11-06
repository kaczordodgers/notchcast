import Foundation

nonisolated enum ArchiveFallbackLimits {
    static func maximumBytes(archiveBytes: Int64) -> Int64 {
        let product = max(archiveBytes, 1).multipliedReportingOverflow(by: 1000)
        return max(5_000_000_000, product.overflow ? Int64.max : product.partialValue)
    }
}
