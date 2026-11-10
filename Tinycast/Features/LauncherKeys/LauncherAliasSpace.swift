enum LauncherAliasSpace {
    struct Entry: Sendable {
        enum Kind: Sendable { case application, systemSettings, command }
        let id: String
        let alias: String?
        let kind: Kind
        var argumentCount = 0
        var hasRequiredArguments = false
        var isViewCommand = false
    }

    enum Decision: Equatable, Sendable {
        case ignore
        case insertLiteralSpace(String)
        case focusFirstArgument(String)
        case openView(String)
        case run(String)
    }

    static func decide(
        query: String, caretUTF16: Int, selectionLength: Int = 0,
        hasModifiers: Bool, entries: [Entry], enabled: Bool, aliases: [String] = []
    ) -> Decision {
        guard enabled, !query.isEmpty, !hasModifiers, selectionLength == 0,
              caretUTF16 == query.utf16.count else { return .ignore }
        if query.hasSuffix("\\") {
            return .insertLiteralSpace(String(query.dropLast()) + " ")
        }
        let matches = entries.filter { $0.alias == query }
        guard matches.count == 1,
              aliases.filter({ $0 == query }).count <= 1,
              !(aliases + entries.compactMap(\.alias)).contains(where: { $0.hasPrefix(query + " ") }),
              let entry = matches.first,
              entry.kind != .application, entry.kind != .systemSettings else { return .ignore }
        if entry.isViewCommand && !entry.hasRequiredArguments { return .openView(entry.id) }
        if entry.argumentCount > 0 { return .focusFirstArgument(entry.id) }
        return .run(entry.id)
    }
}
