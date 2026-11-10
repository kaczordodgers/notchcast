import Foundation
import CoreFoundation

extension NotchcastFeature {
    /// A feature's own settings-backup keys, declared in `<Name>BackupKeys.swift` in its folder.
    struct BackupKeys: Sendable {
        let allowed: [String: BackupValue]
        let excluded: Set<String>
    }

    indirect enum BackupValue: Sendable {
        case bool
        case integer(ClosedRange<Double>)
        case number(ClosedRange<Double>)
        case choices([Double])
        case string(Int, [String] = [])
        case strings(Int, Int)
        case object([String: BackupValue])
        case array(Int, BackupValue)
        case json(BackupValue)
        case optional(BackupValue)
        case colors

        func accepts(_ value: Any) -> Bool {
            switch self {
            case .colors:
                guard let colors = value as? [String], colors.count == 12 else { return false }
                return colors.allSatisfy { color in
                    color.hasPrefix("#") && [7, 9].contains(color.count)
                        && color.dropFirst().utf8.allSatisfy {
                            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                        }
                }
            case .optional(let wrapped):
                return value is NSNull || wrapped.accepts(value)
            case .bool:
                return (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case .integer(let range), .number(let range):
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, range.contains(number.doubleValue) else { return false }
                if case .integer = self { return number.doubleValue.rounded() == number.doubleValue }
                return true
            case .choices(let choices):
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
                return choices.contains(number.doubleValue)
            case .string(let limit, let choices):
                guard let string = value as? String else { return false }
                return string.count <= limit && (choices.isEmpty || choices.contains(string))
            case .strings(let count, let length):
                guard let strings = value as? [String] else { return false }
                return strings.count <= count && strings.allSatisfy { $0.count <= length }
            case .object(let fields):
                guard let object = value as? [String: Any], Set(object.keys).isSubset(of: Set(fields.keys)) else { return false }
                return fields.allSatisfy { $0.value.accepts(object[$0.key] ?? NSNull()) }
            case .array(let limit, let element):
                guard let array = value as? [Any], array.count <= limit else { return false }
                return array.allSatisfy(element.accepts)
            case .json(let shape):
                guard let string = value as? String, string.utf8.count <= 262_144,
                      let object = try? JSONSerialization.jsonObject(
                        with: Data(string.utf8), options: .fragmentsAllowed) else { return false }
                return shape.accepts(object)
            }
        }
    }
}
