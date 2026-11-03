import Foundation
import IOKit

nonisolated struct GPUService: Sendable {
    func read() -> [GPUReading] {
        PowerRegistryAccess.read("IOAccelerator") { entry, properties -> GPUReading? in
            guard let statistics = properties["PerformanceStatistics"] as? [String: Any] else { return nil }
            let modelValue = IORegistryEntrySearchCFProperty(
                entry, kIOServicePlane, "model" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            let model = modelValue as? String ?? (modelValue as? Data).flatMap {
                String(bytes: $0, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            }
            guard let model, !model.isEmpty else { return nil }
            return GPUReading.decode(id: PowerRegistryAccess.id(entry), model: model, statistics: statistics)
        }
    }
}
