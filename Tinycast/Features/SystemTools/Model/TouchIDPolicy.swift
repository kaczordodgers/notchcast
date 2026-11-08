import Foundation

nonisolated enum TouchIDPolicy {
    enum Failure: Error { case missingInclude, unsupportedRule }
    static let rule = "auth       sufficient     pam_tid.so"

    static func enabled(in text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { fields($0) == ["auth", "sufficient", "pam_tid.so"] }
    }

    static func replacement(sudo: String, local: String?, enabled: Bool) throws -> String? {
        guard sudo.components(separatedBy: .newlines).contains(where: {
            fields($0) == ["auth", "include", "sudo_local"]
        }) else { throw Failure.missingInclude }
        guard !Self.enabled(in: sudo) else { throw Failure.unsupportedRule }
        let original = local ?? ""
        let lines = original.components(separatedBy: "\n")
        guard !lines.contains(where: {
            let tokens = fields($0)
            return tokens.contains("pam_tid.so") && tokens != ["auth", "sufficient", "pam_tid.so"]
        }) else { throw Failure.unsupportedRule }
        if Self.enabled(in: original) == enabled { return nil }
        if enabled { return original + (original.isEmpty || original.hasSuffix("\n") ? "" : "\n") + rule + "\n" }
        return lines.filter { fields($0) != ["auth", "sufficient", "pam_tid.so"] }.joined(separator: "\n")
    }

    private static func fields(_ line: String) -> [String] {
        String(line.split(separator: "#", omittingEmptySubsequences: false)[0])
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
