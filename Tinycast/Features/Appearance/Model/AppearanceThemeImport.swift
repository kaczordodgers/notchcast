import Foundation

struct AppearanceThemeImport: Identifiable, Equatable, Sendable {
    enum Choice: Sendable {
        case useTheme, justAdd, cancel
    }

    let id: UUID
    let target: RaycastThemeLink.Target

    var title: String {
        let name = target.theme?.name ?? String(localized: "Default")
        switch target.appearance {
        case .light: return String(localized: "Use “\(name)” as your light theme?")
        case .dark: return String(localized: "Use “\(name)” as your dark theme?")
        }
    }

    var message: String {
        String(localized: "Just Add keeps the theme in your library without changing your colors.")
    }

    static var useThemeTitle: String { String(localized: "Use Theme") }
    static var justAddTitle: String { String(localized: "Just Add") }
    static var cancelTitle: String { String(localized: "Cancel") }
}
