import Foundation

enum HostCommandProfile {
    @concurrent
    static func load(file: URL, host: String) async -> [HostCommandCatalog.Entry] {
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([HostCommandCatalog.Entry].self, from: data),
              let catalog = try? HostCommandCatalog(base: entries, host: host) else { return [] }
        return catalog.entries
    }
}
