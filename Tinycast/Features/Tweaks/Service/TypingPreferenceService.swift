import Foundation
import CoreFoundation

nonisolated struct TypingPreferenceService: Sendable {
    enum Failure: Error { case duplicatePreference, unsupportedValue }

    func readPreference(_ preference: TypingPreferencePlan.Preference) throws -> TypingPreferencePlan.Value? {
        let domain = preference.domain == ".GlobalPreferences"
            ? kCFPreferencesAnyApplication : preference.domain as CFString
        guard let value = CFPreferencesCopyValue(preference.key as CFString, domain,
                                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if CFNumberIsFloatType(number) { return .real(number.doubleValue) }
            return .integer(number.intValue)
        }
        if let string = value as? String { return .string(string) }
        throw Failure.unsupportedValue
    }

    func read(_ writes: [TypingPreferencePlan.Write],
              using reader: (TypingPreferencePlan.Preference) throws -> TypingPreferencePlan.Value?) throws
        -> TypingPreferencePlan {
        guard Set(writes.map(\.preference)).count == writes.count else { throw Failure.duplicatePreference }
        return try TypingPreferencePlan(entries: writes.map { .init(write: $0, previous: try reader($0.preference)) })
    }

    func run(_ commands: [TypingPreferencePlan.Command],
             using runner: (TypingPreferencePlan.Command) throws -> Void) throws {
        for command in commands { try runner(command) }
    }
}
