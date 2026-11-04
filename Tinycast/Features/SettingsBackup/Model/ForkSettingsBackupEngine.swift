import Foundation
import CoreFoundation

enum ForkSettingsBackupEngine {
    enum Failure: Error { case invalidArchive }

    static let ranges: [String: ClosedRange<Double>] = [
        "monitorCPU": 10...100, "monitorTemperature": 40...110,
        "monitorMemory": 0...1, "monitorDisk": 1...50, "monitorBattery": 1...50,
        "batteryChargePercent": 50...100, "keepAwakeMinutes": 15...240,
        "islandHoverDelay": 0.1...1,
    ]

    static func encode(_ preferences: [String: Any], created: Date) throws -> Data {
        let values = try validated(preferences)
        return try PropertyListSerialization.data(
            fromPropertyList: ["format": 1, "created": created, "preferences": values],
            format: .binary, options: 0)
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_048_576,
              let root = try PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any],
              let version = root["format"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              root["created"] is Date,
              let values = root["preferences"] as? [String: Any] else {
            throw Failure.invalidArchive
        }
        return try validated(values)
    }

    static func restored(_ data: Data, current: [String: Any]) throws -> [String: Any] {
        current.merging(try decode(data)) { _, restored in restored }
    }

    private static func validated(_ values: [String: Any]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, range) in ranges {
            guard let value = values[key] else { continue }
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, range.contains(number.doubleValue) else {
                throw Failure.invalidArchive
            }
            result[key] = number
        }
        return result
    }
}
