import Foundation

nonisolated struct TweakCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]

    static func preference(_ preference: TweakPreference, value: TweakValue) -> Self {
        var arguments = preference.currentHost ? ["-currentHost"] : []
        let domain = preference.domain
        switch value {
        case .absent:
            arguments += ["delete", domain, preference.key]
        case .bool(let value):
            arguments += ["write", domain, preference.key, "-bool", value ? "true" : "false"]
        case .integer(let value):
            arguments += ["write", domain, preference.key, "-int", String(value)]
        case .real(let value):
            arguments += ["write", domain, preference.key, "-float", String(value)]
        case .string(let value):
            arguments += ["write", domain, preference.key, "-string", value]
        }
        return Self(executable: "/usr/bin/defaults", arguments: arguments)
    }
}
