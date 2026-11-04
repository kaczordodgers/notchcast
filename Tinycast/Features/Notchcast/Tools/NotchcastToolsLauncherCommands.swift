import Foundation

enum NotchcastToolsLauncherCommands {
    @MainActor static weak var controller: NotchcastToolsCommands?

    static let all = NotchcastToolsCommands.Action.allCases.map { action in
        NotchcastCommand(slug: action.rawValue, name: action.name, sfSymbol: "wrench.and.screwdriver",
            isEnabled: { controller?.isEnabled(action) ?? false },
            run: { controller?.perform(action) })
    }
}
