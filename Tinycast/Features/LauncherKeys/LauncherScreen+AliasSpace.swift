import SwiftUI

extension LauncherScreen {
    func aliasSpace(caretUTF16: Int, selectionLength: Int, hasModifiers: Bool) -> LauncherAliasSpace.Decision {
        let candidates: [LauncherAliasSpace.Entry] = rows.compactMap { row in
            guard case .entry(let app) = row,
                  let alias = core.aliases.alias(for: app.preferenceKey), alias == vm.query else { return nil }
            var entry = LauncherAliasSpace.Entry(
                id: app.id, alias: alias,
                kind: app.kind == .application ? .application
                    : app.kind == .systemSettings ? .systemSettings : .command)
            switch app.kind {
            case .quicklink:
                entry.argumentCount = core.quicklinks.quicklink(entryID: app.id).map {
                    SnippetTemplateEngine.declaredArguments(in: $0.link).count
                } ?? 0
            case .customCommand:
                entry.argumentCount = core.customCommands.command(entryID: app.id)?.arguments.count ?? 0
            case .extensionCommand:
                guard core.settings.extensionsEnabled else { return nil }
                let command = core.extensions.resolve(app)?.1
                entry.argumentCount = command?.arguments.count ?? 0
                entry.hasRequiredArguments = command?.arguments.contains(where: \.required) ?? false
                entry.isViewCommand = command?.mode == .view
            default:
                entry.argumentCount = NotchcastCommandCatalog.command(for: app.id)?.argumentCount ?? 0
            }
            return entry
        }
        let decision = LauncherAliasSpace.decide(
            query: vm.query, caretUTF16: caretUTF16, selectionLength: selectionLength,
            hasModifiers: hasModifiers, entries: candidates, enabled: true,
            aliases: Array(core.aliases.aliases.values))
        let id: String
        switch decision {
        case .ignore: return .ignore
        case .insertLiteralSpace(let query):
            vm.query = query
            return decision
        case .focusFirstArgument(let target), .openView(let target), .run(let target): id = target
        }
        guard let index = rows.firstIndex(where: {
            if case .entry(let app) = $0 { return app.id == id }
            return false
        }) else { return .ignore }
        vm.selection = index
        switch decision {
        case .run, .openView: activate(at: index)
        default: break
        }
        return decision
    }
}
