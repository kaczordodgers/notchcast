/// What fork modules need from the app, set once in `NotchcastCore.start`; harnesses inject what they test.
@MainActor
struct NotchcastHost {
    static var current = NotchcastHost()

    var showMessage: @MainActor (String, DialogTone) -> Void = { _, _ in }
    var remoteResult: @MainActor (String) -> Void = { _ in }
    var refreshNotchcastCommands: @MainActor () -> Void = {}
    var showLauncher: @MainActor () -> Void = {}
    var dismissPalette: @MainActor () -> Void = {}
    var showAppearanceSettings: @MainActor () -> Void = {}
    var showSpotifySettings: @MainActor () -> Void = {}
    var showLinkSettings: @MainActor () -> Void = {}
    var appearanceEnabled: @MainActor () -> Bool = { false }
    var showThemes: @MainActor () -> Void = {}
    var choose: @MainActor (_ title: String, _ message: String?, _ symbol: String,
                           _ options: [String], _ cancelTitle: String) async -> Int = { _, _, _, options, _ in options.count }
    var finderSelection: @MainActor () async throws -> [String] = { [] }
    var browserAddresses: @MainActor (_ processID: Int32, _ bundleID: String?) async throws -> [String] = { _, _ in [] }
    var confirm: @MainActor (_ title: String, _ message: String, _ symbol: String, _ confirmTitle: String) async -> Bool =
        { _, _, _, _ in false }
}
