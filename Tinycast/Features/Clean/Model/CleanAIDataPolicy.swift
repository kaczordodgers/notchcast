import Foundation

struct CleanAIDataPolicy: Sendable {
    static let defaultAge: TimeInterval = 15 * 86_400
    let home: URL
    let age: TimeInterval

    func permits(_ url: URL, kind: CleanAIDataItem.Kind) -> Bool {
        let path = url.standardizedFileURL.path
        guard !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { return false }
        let roots: [String]
        switch kind {
        case .claude: roots = [".claude/projects"]
        case .codex: roots = [".codex/sessions"]
        case .openCode: roots = [".local/share/opencode/storage/session"]
        case .worktree: roots = [".claude/worktrees", ".codex/worktrees", "agents/wt"]
        }
        return roots.contains { root in
            let prefix = home.appendingPathComponent(root).standardizedFileURL.path + "/"
            guard path.hasPrefix(prefix) else { return false }
            let parts = path.dropFirst(prefix.count).split(separator: "/")
            guard parts.allSatisfy({ !$0.hasPrefix(".") }) else { return false }
            if kind == .worktree { return parts.count == 1 }
            if kind == .claude {
                return parts.count == 2 && url.pathExtension == "jsonl"
                    && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
            }
            return url.pathExtension == "jsonl" || url.pathExtension == "json"
        }
    }
}
