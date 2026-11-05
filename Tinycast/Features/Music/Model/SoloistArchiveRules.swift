import Foundation

enum SoloistArchiveRules {
    struct Entry: Equatable, Sendable {
        let kind: Character
        let size: Int
        let name: String
    }

    static let maxPacked = 80 << 20
    static let maxUnpacked = 160 << 20
    static let maxEntries = 64
    static let taken = ["soloist", "THIRD_PARTY_LICENSES.txt", "CHANGELOG.md"]

    static func entries(_ listing: String) throws -> [Entry] {
        let lines = listing.split(separator: "\n")
        guard lines.count <= maxEntries else { throw SoloistFailure.archive.detail("\(lines.count) entries") }
        return try lines.map { line in
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count >= 9, let kind = words[0].first, let size = Int(words[4]) else {
                throw SoloistFailure.archive.detail("tar -tv: \(line.prefix(200))")
            }
            return Entry(kind: kind, size: size, name: words[8...].joined(separator: " "))
        }
    }

    static func check(_ entries: [Entry]) throws -> [String] {
        guard entries.count <= maxEntries else { throw SoloistFailure.archive.detail("\(entries.count) entries") }
        var total = 0
        var seen: Set<String> = []
        var files: [String] = []
        for entry in entries {
            let name = entry.name.hasPrefix("./") ? String(entry.name.dropFirst(2)) : entry.name
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard entry.kind == "-" || entry.kind == "d", entry.size >= 0,
                  entry.size <= maxUnpacked - total, !name.hasPrefix("/"), !name.hasPrefix("-"),
                  !components.contains(".."), !name.contains("\\"),
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  seen.insert(name).inserted else {
                let shown = entry.name.debugDescription.prefix(200)
                throw SoloistFailure.archive.detail("entry \(entry.kind) \(entry.size) \(shown)")
            }
            total += entry.size
            if entry.kind == "-", taken.contains(name) { files.append(entry.name) }
        }
        guard files.contains("soloist") || files.contains("./soloist") else {
            throw SoloistFailure.archive.detail("no soloist entry")
        }
        return files
    }
}
