// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation
import IOKit

nonisolated struct DiskSampler: Sendable {
    private var previous: [UInt64: DiskIOReading.Counters] = [:]
    private var previousTime: TimeInterval?

    func read() -> [DiskVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsLocalKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) ?? []
        return urls.compactMap { url in
            guard !url.path.hasPrefix("/System/Volumes/"),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal != false else { return nil }
            // Finder presents the boot volume as writable despite its sealed root snapshot.
            let capacityURL = url.path == "/" ? URL(filePath: "/System/Volumes/Data") : url
            guard let capacity = try? capacityURL.resourceValues(forKeys: keys),
                  let total = capacity.volumeTotalCapacity, total > 0,
                  let available = capacity.volumeAvailableCapacity, available >= 0 else { return nil }
            return DiskVolume(name: values.volumeName ?? url.lastPathComponent,
                              mountPath: url.path, total: UInt64(total),
                              available: UInt64(min(total, available)),
                              isReadOnly: capacity.volumeIsReadOnly == true)
        }.sorted { $0.mountPath < $1.mountPath }
    }

    // The purge service can be slow; callers request this separately from regular sampling.
    func readAvailableIncludingPurgeable(at mountPath: String) -> UInt64? {
        let url = URL(filePath: mountPath == "/" ? "/System/Volumes/Data" : mountPath)
        guard let writable = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
              writable.volumeIsReadOnly == false,
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage,
              available >= 0 else { return nil }
        return UInt64(available)
    }

    mutating func sample(now: TimeInterval) -> [DiskIOReading] {
        guard now.isFinite else { return [] }
        let counters = readCounters()
        defer {
            previous = counters
            previousTime = now
        }
        return counters.map { id, current in
            let old = previous[id]
            let elapsed = previousTime.map { now - $0 } ?? 0
            return DiskIOReading(
                id: id,
                readBytesPerSecond: old.flatMap {
                    DiskIOReading.rate(current: current.read, previous: $0.read, elapsed: elapsed)
                },
                writeBytesPerSecond: old.flatMap {
                    DiskIOReading.rate(current: current.written, previous: $0.written, elapsed: elapsed)
                })
        }.sorted { $0.id < $1.id }
    }

    private func readCounters() -> [UInt64: DiskIOReading.Counters] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [UInt64: DiskIOReading.Counters] = [:]
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
               let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString,
                   kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let read = stats["Bytes (Read)"] as? NSNumber,
               let written = stats["Bytes (Write)"] as? NSNumber {
                result[id] = .init(read: read.uint64Value, written: written.uint64Value)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return result
    }
}
