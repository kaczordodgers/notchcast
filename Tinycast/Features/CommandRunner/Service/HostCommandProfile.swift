import Foundation
import Darwin

enum HostCommandProfile {
    @concurrent
    static func load(file: URL, host: String? = nil) async throws -> [HostCommandCatalog.Entry] {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        let status = gethostname(&name, name.count)
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let hostname = host ?? (status == 0 ? String(bytes: bytes, encoding: .utf8) ?? "" : "")
        let data = try Data(contentsOf: file)
        let entries = try JSONDecoder().decode([HostCommandCatalog.Entry].self, from: data)
        let catalog = try HostCommandCatalog(base: entries, host: hostname)
        return catalog.entries
    }
}
