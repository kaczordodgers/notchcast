import Foundation

enum AgentSessionExclusions {
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
            guard !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = line.dropFirst(7) }
            let fields = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "NOTCHCAST_AGENT_SESSIONS_EXCLUDE" else { continue }
            value = fields[1]
        }
        guard var value = value.map({ Substring($0.trimmingCharacters(in: .whitespaces)) }) else { return [] }
        if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
            value = value.dropFirst().dropLast()
        }
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}
