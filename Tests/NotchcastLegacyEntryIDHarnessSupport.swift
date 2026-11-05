enum NotchcastCommandCatalog {
    static func command(for id: String) -> String? {
        id == "command:toggle-island" ? id : nil
    }
}
