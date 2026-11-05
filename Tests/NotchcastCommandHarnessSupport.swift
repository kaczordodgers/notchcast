import Foundation

enum NotchcastCommandCatalog {
    struct Command {
        var owner: SettingsTab? { nil }
    }

    static var entries: [AppEntry] { [] }
    static func command(for id: String) -> Command? { nil }
    @MainActor static func isEnabled(_ id: String) -> Bool { true }
}

extension Array where Element == AppEntry {
    func appendingNotchcastCommands() -> [AppEntry] { self }
}
