import Foundation

struct CleanSystemRootClient: Sendable {
    enum Failure: Error { case helperUpdate, refused, invalidResponse }
    let run: @Sendable (RootContract.Command, Data) async throws -> Data
    let policy: CleanSystemPolicy

    func list() async throws -> [CleanSystemEntry] {
        try await checkVersion()
        let data = try await run(.cleanSystemList, Data())
        guard String(bytes: data, encoding: .utf8) != nil else { throw Failure.invalidResponse }
        let entries = try JSONDecoder().decode([CleanSystemEntry].self, from: data)
        guard entries.allSatisfy({ policy.reason(for: $0) != nil }) else { throw Failure.refused }
        return entries
    }

    func trash(_ entry: CleanSystemEntry) async throws {
        guard policy.reason(for: entry) != nil else { throw Failure.refused }
        guard try await run(.cleanSystemTrash, JSONEncoder().encode(entry))
                == Data(RootContract.Command.cleanSystemTrash.output.utf8)
        else { throw Failure.invalidResponse }
    }

    func trash(_ entries: [CleanSystemEntry]) async throws -> Int {
        try await checkVersion()
        var skipped = 0
        for entry in entries {
            try Task.checkCancellation()
            do {
                try await trash(entry)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skipped += 1
            }
        }
        return skipped
    }

    func checkVersion() async throws {
        guard try await run(.version, Data()) == Data(RootContract.Command.version.output.utf8)
        else { throw Failure.helperUpdate }
    }
}
