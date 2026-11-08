import Foundation

struct AgentSessionExclusions {
    static func load(from url: URL) throws -> [String] {
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            return []
        }
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "NOTCHCAST_AGENT_SESSIONS_EXCLUDE" else { continue }
            return fields[1].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }
        return []
    }
}
