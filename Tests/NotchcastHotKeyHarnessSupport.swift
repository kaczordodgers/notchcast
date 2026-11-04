enum NotchcastCommandCatalog {
    struct Command {
        let id: String
        let name: String
    }

    static var entries: [Command] { [] }
    static func command(for id: String) -> Command? { nil }
    @MainActor static func perform(_ id: String) {}
}
