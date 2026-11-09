import Foundation

nonisolated enum SystemToolsHelperPolicy {
    // shortcut: every verb is a compiled RootContract case; delete with its Settings callers.
    static func available(_ feature: NotchcastFeature) -> Bool { true }
}
