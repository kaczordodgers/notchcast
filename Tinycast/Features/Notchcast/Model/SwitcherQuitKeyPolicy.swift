enum SwitcherQuitKeyPolicy {
    static func consumes(
        enabled: Bool, isSwitcher: Bool, menuOpen: Bool, composing: Bool,
        query: String, character: String?, hasModifiers: Bool
    ) -> Bool {
        enabled && isSwitcher && !menuOpen && !composing && query.isEmpty
            && !hasModifiers && character == "q"
    }
}
