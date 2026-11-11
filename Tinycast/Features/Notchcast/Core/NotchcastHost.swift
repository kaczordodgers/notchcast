/// What fork modules need from the app, set once in `NotchcastCore.start`; harnesses keep the no-ops.
@MainActor
struct NotchcastHost {
    static var current = NotchcastHost()

    var showMessage: @MainActor (String, DialogTone) -> Void = { _, _ in }
    var remoteResult: @MainActor (String) -> Void = { _ in }
    var refreshNotchcastCommands: @MainActor () -> Void = {}
    var finderSelection: @MainActor () async throws -> [String] = { [] }
    var browserAddresses: @MainActor (_ processID: Int32, _ bundleID: String?) async throws -> [String] = { _, _ in [] }
}
