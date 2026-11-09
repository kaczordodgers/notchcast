/// What fork modules need from the app, set once in `NotchcastCore.start`; harnesses keep the no-ops.
@MainActor
struct NotchcastHost {
    static var current = NotchcastHost()

    var showMessage: @MainActor (String, DialogTone) -> Void = { _, _ in }
    var refreshNotchcastCommands: @MainActor () -> Void = {}
}
