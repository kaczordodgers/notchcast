import Foundation

struct CleanSystemRootClient: Sendable {
    enum Failure: Error { case helperUpdate, refused, invalidResponse }
    let run: @Sendable (RootContract.Command, Data) async throws -> Data
    let policy: CleanSystemPolicy

    func list() async throws -> [CleanSystemEntry] {
        try await checkVersion()
        let data = try await run(.cleanSystemList, Data())
        let entries = try JSONDecoder().decode([CleanSystemEntry].self, from: data)
        guard entries.allSatisfy({ policy.reason(for: $0) != nil }) else { throw Failure.refused }
        return entries
    }

    func trash(_ entry: CleanSystemEntry) async throws {
        guard policy.reason(for: entry) != nil else { throw Failure.refused }
        try await checkVersion()
        guard try await run(.cleanSystemTrash, JSONEncoder().encode(entry)) == Data("ok\n".utf8)
        else { throw Failure.invalidResponse }
    }

    private func checkVersion() async throws {
        guard try await run(.version, Data()) == Data((RootContract.version + "\n").utf8)
        else { throw Failure.helperUpdate }
    }
}
