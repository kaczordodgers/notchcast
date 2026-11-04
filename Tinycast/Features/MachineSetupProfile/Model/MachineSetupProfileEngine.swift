import Foundation

enum MachineSetupProfileEngine {
    enum Failure: Error { case unsupportedVersion, unsafeContent, disabled, consentRequired }

    struct Policy: Sendable {
        let appVersion: String
        let fileKeys: [String: Set<String>]
        let moduleKeys: Set<String>
        let tweakIDs: Set<String>
    }

    struct Plan: Equatable, Sendable {
        let profile: MachineSetupProfile
        var destinations: [String] {
            ["backup"] + profile.tweaks.sorted().map { "tweak:" + $0 }
                + profile.files.keys.sorted().map { "file:" + $0 }
                + profile.modules.keys.sorted().map { "module:" + $0 }
        }
    }

    static func plan(_ profile: MachineSetupProfile, policy: Policy) throws -> Plan {
        guard profile.format == 1, profile.appVersion == policy.appVersion else {
            throw Failure.unsupportedVersion
        }
        guard Set(profile.tweaks).count == profile.tweaks.count,
              Set(profile.tweaks).isSubset(of: policy.tweakIDs),
              Set(profile.modules.keys).isSubset(of: policy.moduleKeys),
              profile.modules.allSatisfy({ safe($0.key) && safe($0.value) }),
              profile.files.allSatisfy({ path, values in
                  relative(path) && policy.fileKeys[path].map { allowed in
                      Set(values.keys).isSubset(of: allowed)
                          && values.allSatisfy { safe($0.key) && safe($0.value) }
                  } == true
              }) else { throw Failure.unsafeContent }
        return Plan(profile: profile)
    }

    private static func relative(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let forbidden = [".ssh", ".env", "credentials", "auth.json", "sessions", "history", "skills"]
        return !parts.isEmpty && parts.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
                && !forbidden.contains($0.lowercased()) && !$0.hasPrefix(".env")
                && !$0.contains("\0")
        }
    }

    private static func safe(_ text: String) -> Bool {
        let lower = text.lowercased()
        let forbidden = ["secret", "token", "password", "credential", "apikey", "api_key",
                         "authorization", "snippetsenabled", "/users/", "/library/", "grant"]
        guard !text.contains("\0"), !text.contains("/"),
              !forbidden.contains(where: lower.contains) else { return false }
        return !text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { word in
            word.count >= 24 && Set(word).count >= 12
        }
    }
}
