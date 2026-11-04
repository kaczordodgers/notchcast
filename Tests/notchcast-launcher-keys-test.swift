// notchcast-sources: Tinycast/Features/Launcher/Keys/LauncherNumberKeys.swift
// notchcast-sources: Tinycast/Features/Launcher/Keys/LauncherAliasSpace.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
import Foundation

@main
struct LauncherKeysTest {
    static func main() {
        for digit in 1...9 {
            precondition(LauncherNumberKeys.entryIndex(digit: digit, query: "a", entryCount: 12, enabled: true) == digit - 1)
            precondition(LauncherNumberKeys.entryIndex(digit: digit, query: "", entryCount: 12, enabled: true) == nil)
            precondition(LauncherNumberKeys.entryIndex(digit: digit, query: "a", entryCount: 12, enabled: false) == nil)
            let shortList = LauncherNumberKeys.entryIndex(digit: digit, query: "a", entryCount: 3, enabled: true)
            precondition(shortList == (digit <= 3 ? digit - 1 : nil))
        }
        for digit in [-1, 0, 10] {
            precondition(LauncherNumberKeys.entryIndex(digit: digit, query: "a", entryCount: 12, enabled: true) == nil)
        }
        precondition(LauncherNumberKeys.entryIndex(digit: 1, query: "a", entryCount: 0, enabled: true) == nil)
        typealias Entry = LauncherAliasSpace.Entry
        let entries: [Entry] = [
            .init(id: "run", alias: "r", kind: .command),
            .init(id: "optional", alias: "o", kind: .command, argumentCount: 1),
            .init(id: "required", alias: "q", kind: .command, argumentCount: 2, hasRequiredArguments: true),
            .init(id: "view", alias: "v", kind: .command, argumentCount: 1, isViewCommand: true),
            .init(id: "view-required", alias: "w", kind: .command, argumentCount: 1,
                  hasRequiredArguments: true, isViewCommand: true),
            .init(id: "empty-view", alias: "e", kind: .command, isViewCommand: true),
            .init(id: "app", alias: "a", kind: .application),
            .init(id: "pane", alias: "p", kind: .systemSettings),
            .init(id: "unicode", alias: "😀", kind: .command)
        ]
        func decision(_ query: String, caret: Int? = nil, selection: Int = 0,
                      modifiers: Bool = false, enabled: Bool = true) -> LauncherAliasSpace.Decision {
            LauncherAliasSpace.decide(query: query, caretUTF16: caret ?? query.utf16.count,
                                      selectionLength: selection, hasModifiers: modifiers,
                                      entries: entries, enabled: enabled)
        }
        precondition(decision("r") == .run("run"))
        precondition(decision("o") == .focusFirstArgument("optional"))
        precondition(decision("q") == .focusFirstArgument("required"))
        precondition(decision("v") == .openView("view"))
        precondition(decision("w") == .focusFirstArgument("view-required"))
        precondition(decision("e") == .openView("empty-view"))
        for query in ["", "R", "missing", "a", "p", "r "] {
            precondition(decision(query) == .ignore)
        }
        precondition(decision("r", caret: 0) == .ignore)
        precondition(decision("r", selection: 1) == .ignore)
        precondition(decision("r", modifiers: true) == .ignore)
        precondition(decision("r", enabled: false) == .ignore)
        precondition(decision("r\\") == .insertLiteralSpace("r "))
        precondition(decision("\\") == .insertLiteralSpace(" "))
        precondition(decision("r\\", modifiers: true) == .ignore)
        precondition(decision("r\\", enabled: false) == .ignore)
        precondition(decision("r\\", caret: 1) == .ignore)
        precondition(decision("😀") == .run("unicode"))
        precondition(decision("😀", caret: 1) == .ignore)
        for feature in [NotchcastFeature.launcherNumberKeys, .launcherAliasSpace] {
            precondition(!feature.defaultEnabled && !feature.needsIsland)
            precondition(feature.settingsGroup == .launcher && feature.requiredGrants.isEmpty)
        }
        print("Launcher keys passed")
    }
}
