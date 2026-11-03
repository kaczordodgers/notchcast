import Foundation

nonisolated enum MemoryDecoder {
    static func decode(total: UInt64, pageSize: UInt64, internalPages: UInt64,
                       purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64,
                       externalPages: UInt64, freePages: UInt64, pressureLevel: Int32? = nil,
                       availablePercent: Int32? = nil, swapUsed: UInt64? = nil,
                       swapTotal: UInt64? = nil) -> MemoryReading? {
        guard total > 0, pageSize > 0 else { return nil }
        func bytes(_ pages: UInt64) -> UInt64 {
            let result = pages.multipliedReportingOverflow(by: pageSize)
            return result.overflow ? total : min(total, result.partialValue)
        }
        let app = bytes(internalPages - min(internalPages, purgeablePages))
        let wired = bytes(wiredPages)
        let compressed = bytes(compressedPages)
        let used = app + min(wired, total - app)
        let cached = bytes(externalPages) + min(bytes(purgeablePages), total - bytes(externalPages))
        return MemoryReading(
            total: total, used: used + min(compressed, total - used), app: app,
            wired: wired, compressed: compressed, cached: cached, free: bytes(freePages),
            pressure: pressureLevel.flatMap(MemoryReading.Pressure.init),
            pressurePercent: availablePercent.map { Double(100 - min(100, max(0, $0))) },
            swapUsed: swapUsed, swapTotal: swapTotal)
    }
}
