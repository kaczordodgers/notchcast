// notchcast-sources: Tinycast/Features/Notchcast/Model/SwitcherQuitKeyPolicy.swift
@main
struct SwitcherQuitKeyTest {
    static func main() {
        func consumes(
            enabled: Bool = true, switcher: Bool = true, menu: Bool = false,
            composing: Bool = false, query: String = "", key: String? = "q", modifiers: Bool = false
        ) -> Bool {
            SwitcherQuitKeyPolicy.consumes(
                enabled: enabled, isSwitcher: switcher, menuOpen: menu, composing: composing,
                query: query, character: key, hasModifiers: modifiers)
        }
        precondition(consumes())
        precondition(!consumes(enabled: false))
        precondition(!consumes(switcher: false))
        precondition(!consumes(menu: true))
        precondition(!consumes(composing: true))
        precondition(!consumes(query: "Safari"))
        precondition(!consumes(key: "w"))
        precondition(!consumes(key: nil))
        precondition(!consumes(modifiers: true))
        print("Switcher quit key: 9 checks passed")
    }
}
