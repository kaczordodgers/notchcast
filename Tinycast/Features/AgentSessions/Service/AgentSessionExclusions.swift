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
            if line.hasPrefix("export"), line.dropFirst(6).first?.isWhitespace == true {
                line = line.dropFirst(6).trimmingPrefix(while: \.isWhitespace)
            }
            let fields = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "NOTCHCAST_AGENT_SESSIONS_EXCLUDE" else { continue }
            value = fields[1]
        }
        guard let value else { return [] }
        return shellWord(value).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func shellWord(_ raw: Substring) -> Substring {
        if let quote = raw.first, quote == "\"" || quote == "'",
           let end = raw.dropFirst().firstIndex(of: quote) {
            return raw[raw.index(after: raw.startIndex)..<end]
        }
        return raw.prefix { !$0.isWhitespace && $0 != ";" && $0 != "#" }
    }
}
