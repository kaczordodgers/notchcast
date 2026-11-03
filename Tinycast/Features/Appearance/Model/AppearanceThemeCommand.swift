import Foundation

enum AppearanceThemeCommand {
    struct Row: Identifiable, Equatable, Sendable {
        let target: RaycastThemeLink.Target
        let isSelected: Bool

        var id: String { target.theme?.id ?? "\(target.appearance.rawValue):tinycast" }
        var title: String { target.theme?.name ?? "Tinycast" }
        var subtitle: String { target.theme?.author ?? String(localized: "No theme") }
    }

    static var title: String { String(localized: "Theme") }

    static func rows(
        currentAppearance: RaycastTheme.Appearance, light: RaycastTheme?, dark: RaycastTheme?,
        imported: [RaycastTheme], query: String = ""
    ) -> [Row] {
        let slots: [RaycastTheme.Appearance] = currentAppearance == .dark ? [.dark, .light] : [.light, .dark]
        var themes = imported
        for theme in [light, dark].compactMap({ $0 }) where !themes.contains(where: { $0.id == theme.id }) {
            themes.append(theme)
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return slots.flatMap { slot in
            let current = slot == .dark ? dark : light
            let targets: [RaycastThemeLink.Target] = [.tinycast(slot)]
                + themes.filter { $0.appearance == slot }.map { .theme($0) }
            return targets.map { Row(target: $0, isSelected: $0.theme?.id == current?.id) }.filter {
                query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.subtitle.localizedCaseInsensitiveContains(query)
            }
        }
    }
}
