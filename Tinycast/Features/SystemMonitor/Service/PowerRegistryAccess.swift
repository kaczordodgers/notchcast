import Foundation
import IOKit

nonisolated enum PowerRegistryAccess {
    static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
            == KERN_SUCCESS else { return [:] }
        return properties?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    static func read<Value>(_ className: String, copyAll: Bool = true,
                            decode: (io_registry_entry_t, [String: Any]) -> Value?) -> [Value] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator)
            == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [Value] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let value = decode(entry, copyAll ? properties(entry) : [:]) { result.append(value) }
        }
        return result
    }

    static func id(_ entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }
}
