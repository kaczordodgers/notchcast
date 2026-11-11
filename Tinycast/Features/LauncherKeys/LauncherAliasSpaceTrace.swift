import OSLog

/// Evidence for a refused alias Space: gates and counts, never the query, built only for debug logs.
enum LauncherAliasSpaceTrace {
    private static let log = Logger(subsystem: NotchcastIdentity.current.bundleID, category: "AliasSpace")

    static func note(_ message: @autoclosure @escaping () -> String) { log.debug("\(message(), privacy: .public)") }
}

extension LauncherAliasSpace.Decision {
    var traceName: String {
        switch self {
        case .ignore: "ignore"
        case .insertLiteralSpace: "insertLiteralSpace"
        case .focusFirstArgument: "focusFirstArgument"
        case .openView: "openView"
        case .run: "run"
        }
    }
}
