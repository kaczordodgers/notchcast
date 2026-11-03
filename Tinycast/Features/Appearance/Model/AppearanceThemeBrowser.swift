import Foundation

enum AppearanceThemeBrowser {
    struct Section: Equatable, Sendable {
        let imported: [RaycastTheme]
        let bundled: [RaycastTheme]
    }

    static func themes(
        for slot: RaycastTheme.Appearance, query: String, imported: [RaycastTheme],
        catalog: [RaycastTheme] = RaycastThemeCatalog.all
    ) -> Section {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ theme: RaycastTheme) -> Bool {
            theme.appearance == slot && (query.isEmpty || theme.name.localizedCaseInsensitiveContains(query)
                || theme.author.localizedCaseInsensitiveContains(query))
        }
        let importedIDs = Set(imported.map(\.id))
        return Section(
            imported: imported.filter(matches),
            bundled: catalog.filter { !importedIDs.contains($0.id) && matches($0) })
    }
}
