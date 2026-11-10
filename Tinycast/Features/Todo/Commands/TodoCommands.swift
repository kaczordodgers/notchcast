import AppKit

@MainActor
enum TodoCommands {
    nonisolated static let addFromClipboard = commands(context: { context })[0]
    nonisolated static let completeNext = commands(context: { context })[1]
    nonisolated static let undoLast = commands(context: { context })[2]

    static var enabled: Bool { NotchcastPreferences.shared.isEnabled(.tasks) }

    nonisolated static func commands(
        context: @escaping @MainActor @Sendable () -> TodoCommandContext
    ) -> [NotchcastCommand] {
        [NotchcastCommand(slug: "add-task-from-clipboard", name: String(localized: "Add Task from Clipboard", table: "Notchcast"),
                         sfSymbol: "clipboard", feature: .tasks,
                         isEnabled: { context().isEnabled() }, run: { context().add() }),
         NotchcastCommand(slug: "complete-next-task", name: String(localized: "Complete Next Task", table: "Notchcast"),
                         sfSymbol: "checkmark.circle", feature: .tasks,
                         isEnabled: { context().isEnabled() }, run: { context().complete() }),
         NotchcastCommand(slug: "undo-last-task-change", name: String(localized: "Undo Last Task Change", table: "Notchcast"),
                         sfSymbol: "arrow.uturn.backward", feature: .tasks,
                         isEnabled: { context().isEnabled() }, run: { context().undo() })]
    }

    static var context: TodoCommandContext {
        TodoCommandContext(isEnabled: { enabled }, store: { TodoModule.shared?.store },
                           clipboardText: { NSPasteboard.general.string(forType: .string) },
                           report: { AppCore.shared.showMessage($0) })
    }
}
