import Foundation

@main
struct MemoryDiskTests {
    static func main() {
        let memory = MemoryDecoder.decode(
            total: 1_000, pageSize: 10, internalPages: 30, purgeablePages: 5,
            wiredPages: 10, compressedPages: 5, externalPages: 20, freePages: 10,
            pressureLevel: 2, availablePercent: 70, swapUsed: 20, swapTotal: 100)!
        precondition(memory.app == 250 && memory.wired == 100 && memory.compressed == 50)
        precondition(memory.used == 400 && memory.cached == 250 && memory.free == 100)
        precondition(memory.pressure == .warning && memory.pressurePercent == 30)
        precondition(memory.swapUsed == 20 && memory.swapTotal == 100)
        precondition(MemoryReading.Pressure(rawValue: 1) == .normal)
        precondition(MemoryReading.Pressure(rawValue: 4) == .critical)
        precondition(MemoryReading.Pressure(rawValue: 0) == nil)
        let overflow = MemoryDecoder.decode(
            total: 1_000, pageSize: 16_384, internalPages: .max, purgeablePages: 0,
            wiredPages: .max, compressedPages: .max, externalPages: .max, freePages: .max)!
        precondition(overflow.used == 1_000 && overflow.cached == 1_000)
        let underflow = MemoryDecoder.decode(
            total: 100, pageSize: 1, internalPages: 1, purgeablePages: 2,
            wiredPages: 0, compressedPages: 0, externalPages: 0, freePages: 0)!
        precondition(underflow.app == 0 && underflow.pressurePercent == nil)
        precondition(MemoryDecoder.decode(
            total: 0, pageSize: 1, internalPages: 0, purgeablePages: 0,
            wiredPages: 0, compressedPages: 0, externalPages: 0, freePages: 0) == nil)
        precondition(DiskIOReading.rate(current: 300, previous: 100, elapsed: 2) == 100)
        precondition(DiskIOReading.rate(current: 1, previous: 100, elapsed: 2) == nil)
        precondition(DiskIOReading.rate(current: 100, previous: 0, elapsed: 0) == nil)
        precondition(DiskIOReading.rate(current: 100, previous: 0, elapsed: 16) == nil)
        precondition(DiskIOReading.rate(current: 100, previous: 0, elapsed: .nan) == nil)
        let volume = DiskVolume(name: "Test", mountPath: "/", total: 100, available: 9)
        precondition(volume.isLowSpace() && !volume.isLowSpace(thresholdPercent: 9))
        precondition(!DiskVolume(name: "", mountPath: "", total: 0, available: 0).isLowSpace())
        if let live = MemorySampler().read() {
            precondition(live.total > 0 && live.used <= live.total)
            precondition(live.pressurePercent.map { (0...100).contains($0) } ?? true)
        }
        var disk = DiskSampler()
        for live in disk.read() {
            precondition(live.total > 0 && live.available <= live.total)
            precondition(live.mountPath.hasPrefix("/"))
        }
        precondition(disk.sample(now: ProcessInfo.processInfo.systemUptime)
            .allSatisfy { $0.readBytesPerSecond == nil && $0.writeBytesPerSecond == nil })
        let purgeable = disk.readAvailableIncludingPurgeable(at: "/System/Volumes/Data")
        precondition(purgeable.map { $0 <= UInt64(Int64.max) } ?? true)
        print("Memory/disk fixed-input and live shape checks passed")
    }
}
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
