import Foundation

enum AgentSessionExclusions {
    struct MalformedAssignment: Error {}
    private static let key = "NOTCHCAST_AGENT_SESSIONS_EXCLUDE"

    static func load(from url: URL) throws -> [String] {
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            return []
        }
        var value: Substring?
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingPrefix(while: \.isWhitespace)
            guard !line.hasPrefix("#"), line.contains(key) else { continue }
            if line.hasPrefix("export"), line.dropFirst(6).first?.isWhitespace == true {
                line = line.dropFirst(6).trimmingPrefix(while: \.isWhitespace)
            }
            guard line.hasPrefix(key + "=") else { throw MalformedAssignment() }
            value = try shellWord(line.dropFirst(key.count + 1))
        }
        guard let value else { return [] }
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    // Fails closed: anything a shell could read differently from this parser throws.
    private static func shellWord(_ raw: Substring) throws -> Substring {
        let word: Substring
        let rest: Substring
        if let quote = raw.first, quote == "\"" || quote == "'" {
            guard let end = raw.dropFirst().firstIndex(of: quote) else { throw MalformedAssignment() }
            word = raw[raw.index(after: raw.startIndex)..<end]
            rest = raw[raw.index(after: end)...]
        } else {
            word = raw.prefix { !$0.isWhitespace && $0 != ";" }
            rest = raw[word.endIndex...]
            guard !word.contains(where: { $0 == "\"" || $0 == "'" }) else { throw MalformedAssignment() }
        }
        let tail = rest.trimmingPrefix(while: \.isWhitespace)
        let spaced = tail.startIndex != rest.startIndex
        guard tail.isEmpty || (spaced && tail.hasPrefix("#")) || (tail.hasPrefix(";") && !tail.contains(key))
        else { throw MalformedAssignment() }
        return word
    }
}
