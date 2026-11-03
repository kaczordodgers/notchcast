import Foundation

struct RaycastThemeLink: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case theme(RaycastTheme)
        case tinycast(RaycastTheme.Appearance)

        var appearance: RaycastTheme.Appearance {
            switch self {
            case .theme(let theme): theme.appearance
            case .tinycast(let slot): slot
            }
        }

        var theme: RaycastTheme? {
            if case .theme(let theme) = self { return theme }
            return nil
        }
    }

    let target: Target
    let applies: Bool

    init?(url: URL, applicationScheme: String) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = parts.scheme?.lowercased(),
            ["raycast", applicationScheme.lowercased()].contains(scheme),
            parts.host?.lowercased() == "theme", parts.user == nil, parts.password == nil,
            parts.port == nil, parts.path.isEmpty, parts.fragment == nil
        else { return nil }
        let items = parts.queryItems ?? []
        let keys = ["name", "author", "authorUsername", "appearance", "colors", "none", "apply"]
        guard keys.allSatisfy({ key in items.filter { $0.name == key }.count <= 1 }) else { return nil }
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
        applies = value("apply") == "1"
        if let rawSlot = value("none") {
            guard value("name") == nil, value("colors") == nil,
                let slot = RaycastTheme.Appearance(rawValue: rawSlot)
            else { return nil }
            target = .tinycast(slot)
            return
        }
        guard let name = value("name"), let rawColors = value("colors"),
            let appearance = value("appearance").flatMap(RaycastTheme.Appearance.init(rawValue:))
        else { return nil }
        let theme = RaycastTheme(
            name: name, author: value("author") ?? value("authorUsername") ?? "", appearance: appearance,
            colors: rawColors.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
        guard theme.isValid else { return nil }
        target = .theme(theme)
    }
}
