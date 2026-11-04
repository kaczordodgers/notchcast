import Foundation

@MainActor
struct LinkQuickFixExecutor {
    var copy: (String) -> Void
    var open: (URL) -> Void
    var settings: () -> Void
    var message: (String) -> Void

    func run(_ action: LinkQuickFixEngine.Action) {
        switch action {
        case let .copyCommand(command, _):
            copy(command)
            message(String(localized: "Command copied."))
        case .openNetworkSettings:
            open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)
        case .relinkInConnections:
            settings()
        case let .openMirrorLog(url):
            open(url)
        }
    }
}
