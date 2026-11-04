import Foundation

nonisolated enum ArchiveRules {
    static func validate(_ listing: ArchiveListing, archiveBytes: Int64) throws {
        guard let total = listing.totalBytes else { throw ArchiveFailure.invalidListing }
        if total > 5_000_000_000, Double(total) / Double(max(archiveBytes, 1)) > 1000 {
            throw ArchiveFailure.expansionLimit
        }
        var paths: [String: String] = [:]
        var links = Set<String>()
        var files = Set<String>()
        for entry in listing.entries {
            let components = try components(entry.path)
            guard !components.isEmpty else { continue }
            var prefix: [String] = []
            for component in components {
                prefix.append(component)
                let original = prefix.joined(separator: "/")
                let key = folded(original)
                if let prior = paths[key], prior != original { throw ArchiveFailure.collision(entry.path) }
                paths[key] = original
            }
            let key = folded(components.joined(separator: "/"))
            if entry.isSymlink { links.insert(key) }
            if !entry.isDirectory { files.insert(key) }
        }
        var seen = Set<String>()
        for entry in listing.entries {
            let components = try components(entry.path)
            guard !components.isEmpty else { continue }
            let key = folded(components.joined(separator: "/"))
            guard seen.insert(key).inserted else { throw ArchiveFailure.collision(entry.path) }
            for depth in 1..<components.count {
                let ancestor = folded(components.prefix(depth).joined(separator: "/"))
                if links.contains(ancestor) { throw ArchiveFailure.symlinkAncestor(entry.path) }
                if files.contains(ancestor) { throw ArchiveFailure.collision(entry.path) }
            }
        }
    }

    static func components(_ path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
            throw ArchiveFailure.unsafePath(path)
        }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains("..") else { throw ArchiveFailure.unsafePath(path) }
        return parts.filter { $0 != "." }
    }

    private static func folded(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}
