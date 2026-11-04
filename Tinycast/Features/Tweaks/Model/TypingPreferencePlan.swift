import Foundation

nonisolated struct TypingPreferencePlan: Sendable, Equatable, Codable {
    enum Value: Sendable, Equatable, Codable {
        case bool(Bool), integer(Int), real(Double), string(String)

        var arguments: [String] {
            switch self {
            case .bool(let value): ["-bool", value ? "true" : "false"]
            case .integer(let value): ["-int", String(value)]
            case .real(let value): ["-float", String(value)]
            case .string(let value): ["-string", value]
            }
        }
    }

    struct Preference: Sendable, Equatable, Codable, Hashable {
        let domain: String
        let key: String
    }

    struct Write: Sendable, Equatable, Codable {
        let preference: Preference
        let value: Value

        init(_ domain: String, _ key: String, _ value: Value) {
            preference = Preference(domain: domain, key: key)
            self.value = value
        }

        init(_ key: String, _ value: Value) {
            self.init(".GlobalPreferences", key, value)
        }
    }

    struct Command: Sendable, Equatable, Codable {
        let executable: String
        let arguments: [String]
    }

    struct Entry: Sendable, Equatable, Codable {
        let write: Write
        let previous: Value?
    }

    let entries: [Entry]
    let extraApply: [Command]?
    let extraRevert: [Command]?

    init(entries: [Entry], extraApply: [Command]? = nil, extraRevert: [Command]? = nil) {
        self.entries = entries
        self.extraApply = extraApply
        self.extraRevert = extraRevert
    }

    var apply: [Command] { entries.map { Self.command($0.write.preference, value: $0.write.value) } + (extraApply ?? []) }
    var revert: [Command] {
        (extraRevert ?? []) + entries.reversed().map { Self.command($0.write.preference, value: $0.previous) }
    }

    private static func command(_ preference: Preference, value: Value?) -> Command {
        Command(executable: "/usr/bin/defaults", arguments: value.map {
            ["write", preference.domain, preference.key] + $0.arguments
        } ?? ["delete", preference.domain, preference.key])
    }
}
