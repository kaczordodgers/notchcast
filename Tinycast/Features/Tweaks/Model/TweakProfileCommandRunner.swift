import Foundation

enum TweakProfileCommandRunner {
    @MainActor
    static func run(ai: Bool, enabled: () -> Bool, confirm: () async -> Bool,
                    request: (Set<String>?, Set<String>) async throws -> Void) async throws {
        guard enabled(), !Task.isCancelled, await confirm(), enabled(), !Task.isCancelled else { return }
        let privacy = ai ? Set<String>() : Set(PrivacyCatalog.restrictions.keys)
            .union(PrivacyCatalog.preferences.keys)
        try await request(ai ? [] : nil, privacy)
    }
}
