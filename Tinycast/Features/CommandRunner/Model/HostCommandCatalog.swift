import Foundation

struct HostCommandCatalog: Sendable, Equatable {
    struct Entry: Codable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let executable: String
        var arguments: [String] = []
        var hosts: Set<String> = []
        var workingDirectory: String?
    }

    enum ProfileError: Error { case invalidEntries, invalidOverride }

    let entries: [Entry]

    init(base: [Entry], overrides: [Entry] = [], host: String) throws {
        guard Set(base.map(\.id)).count == base.count,
              (base + overrides).allSatisfy({
                  !$0.id.isEmpty && !$0.title.isEmpty && $0.executable.hasPrefix("/")
                      && !$0.executable.contains("\0") && !$0.arguments.contains(where: { $0.contains("\0") })
              }) else { throw ProfileError.invalidEntries }
        var merged = base
        var seen: Set<String> = []
        for entry in overrides {
            guard seen.insert(entry.id).inserted,
                  let index = merged.firstIndex(where: { $0.id == entry.id })
            else { throw ProfileError.invalidOverride }
            merged[index] = entry
        }
        entries = merged.filter { $0.hosts.isEmpty || $0.hosts.contains(host) }
    }
}
