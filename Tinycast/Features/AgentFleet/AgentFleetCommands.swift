import Foundation

enum AgentFleetCommands {
    @MainActor static var enabled = false
    @MainActor static var run: (String) -> Void = { _ in }

    static let list = command("list-bots", String(localized: "List Bots"), "list.bullet")
    static let status = command("bot-status", String(localized: "Bot Status"), "circle.dotted")
    static let pending = command("bot-pending", String(localized: "Bot Pending"), "questionmark.circle")

    private static func command(_ slug: String, _ name: String, _ symbol: String) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: symbol,
            isEnabled: { enabled }, run: { run(slug) })
    }
}
