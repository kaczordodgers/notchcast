import Foundation
import CoreFoundation

enum ForkSettingsBackupEngine {
    enum Failure: Error { case invalidArchive }

    static let maximumSize = 1_048_576

    static func encode(_ preferences: [String: Any], created: Date) throws -> Data {
        let values = preferences.filter { ForkSettingsBackupSchema.allowed[$0.key]?.accepts($0.value) == true }
        return try PropertyListSerialization.data(
            fromPropertyList: ["format": 2, "created": created, "preferences": values],
            format: .binary, options: 0)
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumSize,
              let root = try PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any],
              Set(root.keys) == ["format", "created", "preferences"],
              let version = root["format"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 2,
              root["created"] is Date,
              let values = root["preferences"] as? [String: Any], !values.isEmpty else {
            throw Failure.invalidArchive
        }
        try validate(values)
        return values
    }

    static func restored(_ data: Data, current: [String: Any]) throws -> [String: Any] {
        current.merging(try decode(data)) { _, restored in restored }
    }

    static func newest(in names: [String]) -> String? {
        names.compactMap { name -> (String, Int)? in
            guard name.hasPrefix("settings-v2-"), name.hasSuffix(".plist") else { return nil }
            let digits = name.dropFirst(12).dropLast(6)
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let day = Int(digits) else { return nil }
            return (name, day)
        }.max { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }?.0
    }

    static func validate(_ values: [String: Any]) throws {
        guard values.allSatisfy({ ForkSettingsBackupSchema.allowed[$0.key]?.accepts($0.value) == true }) else {
            throw Failure.invalidArchive
        }
    }
}
