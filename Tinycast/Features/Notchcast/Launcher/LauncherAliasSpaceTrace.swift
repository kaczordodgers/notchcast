import OSLog

/// Field evidence for a refused alias Space: gates and counts only, never the typed query.
enum LauncherAliasSpaceTrace {
    private static let log = Logger(subsystem: NotchcastIdentity.current.bundleID, category: "AliasSpace")

    static func note(_ message: String) { log.notice("\(message, privacy: .public)") }
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
