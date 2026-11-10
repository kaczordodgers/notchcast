import Foundation

nonisolated enum MacUpdateStep: CaseIterable, Sendable {
    case homebrewUpdate, homebrewUpgrade, commandLineTools, appStore
}

nonisolated struct MacUpdateCommand: Equatable, Sendable {
    var path: String
    var arguments: [String]
    var timeout: Duration = .seconds(900)
}

nonisolated enum MacUpdatePlan: Sendable {
    case commands([MacUpdateCommand])
    case skipped(String)

    static let tools = ["brew", "mas", "npm", "claude", "codex"]

    /// `tools` maps each of `Self.tools` the Mac has to its path.
    static func make(_ step: MacUpdateStep, tools: [String: String], resolve: (String) -> String) -> Self {
        let brew = tools["brew"]
        switch step {
        case .homebrewUpdate, .homebrewUpgrade:
            guard let brew else { return .skipped("missing-homebrew") }
            return .commands([MacUpdateCommand(
                path: brew, arguments: [step == .homebrewUpdate ? "update" : "upgrade"],
                timeout: .seconds(step == .homebrewUpdate ? 900 : 3600))])
        case .appStore:
            guard let mas = tools["mas"] else { return .skipped("missing-mas") }
            return .commands([MacUpdateCommand(path: mas, arguments: ["upgrade"], timeout: .seconds(3600))])
        case .commandLineTools:
            var commands: [MacUpdateCommand] = []
            for (name, package) in [("claude", "@anthropic-ai/claude-code"), ("codex", "@openai/codex")] {
                guard let path = tools[name] else { continue }
                let real = resolve(path)
                let parts = real.split(separator: "/")
                if let index = parts.firstIndex(of: "Caskroom"), parts.indices.contains(index + 1),
                   let brew {
                    commands.append(MacUpdateCommand(
                        path: brew, arguments: ["upgrade", "--cask", "--greedy", String(parts[index + 1])],
                        timeout: .seconds(1800)))
                } else if real.contains("/node_modules/") {
                    guard let npm = tools["npm"] else { continue }
                    commands.append(MacUpdateCommand(path: npm, arguments: ["install", "-g", package + "@latest"]))
                } else if name == "claude" {
                    commands.append(MacUpdateCommand(path: path, arguments: ["update"]))
                }
            }
            return commands.isEmpty ? .skipped("missing-or-unsupported-cli-install") : .commands(commands)
        }
    }

    static func upgradedApps(output: String, root: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let prefix = "==> Moving App '"
            guard line.hasPrefix(prefix), let range = line.range(of: "' to '") else { return nil }
            let suffix = line[range.upperBound...]
            guard suffix.hasSuffix("'") else { return nil }
            let path = String(suffix.dropLast())
            guard path.hasPrefix(root + "/"), path.hasSuffix(".app"),
                  !path.split(separator: "/").contains("..") else { return nil }
            return path
        }
    }
}
