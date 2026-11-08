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
        let lines = contents.split(whereSeparator: \.isNewline).filter { $0.contains(key) }
        guard lines.count <= 1 else { throw MalformedAssignment() }
        guard let line = lines.first else { return [] }
        let assignment = #/
            [\x20\t]* (?: export [\x20\t]+ )? NOTCHCAST_AGENT_SESSIONS_EXCLUDE=
            (?: ([A-Za-z0-9_.,-]*) | "([A-Za-z0-9_.,-]*)" | '([A-Za-z0-9_.,-]*)' )
            (?: [\x20\t]+ (?: \#.* )? )?
            /#
        guard let match = line.wholeMatch(of: assignment) else { throw MalformedAssignment() }
        let value = match.1 ?? match.2 ?? match.3 ?? ""
        return value.split(separator: ",").map { $0.lowercased() }
    }
}
