import Foundation

enum AppPaths { static func applicationSupport() -> URL { FileManager.default.temporaryDirectory } }
enum DialogTone { case neutral, success, danger }
@MainActor final class AppCore {
    let settingsCoordinator = SettingsStub()
    static let shared = AppCore()
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async { }
}
@MainActor final class SettingsStub {
    enum Tab { case notchcast }
    func showSettings(tab: Tab) { }
}
enum NotchcastSettingsModule {
    static func module(of feature: NotchcastFeature) -> Self { .system }
    case system
    var tab: SettingsStub.Tab { .notchcast }
}
enum SettingsActionCommands {
    @MainActor static func show(_ tab: SettingsStub.Tab, _ feature: NotchcastFeature) { }
}
enum ColorPickerFormat: String, CaseIterable { case hex, hexLowercase, rgb, hsl, swiftUIColor, nsColorLiteral }
enum ColorPickerService { static let formatKey = "notchcast.colorPicker.format" }
enum ScreenshotModule {
    static let destinationKey = "notchcast.screenshot.destination"
    static let folderKey = "notchcast.screenshot.folder"
}
enum SpotifyConnectModule { static let deviceNameKey = "spotify.deviceName" }
enum AgentBridgeModule { static let grantsKey = "agentActionGrants" }
enum ArchiveRecovery { static let key = "archiveRecoveryParents" }
@MainActor final class ColorPickerModule {
    static let shared = ColorPickerModule()
    var format = ColorPickerFormat.hex
}
@MainActor final class ScreenTextModule {
    static let shared = ScreenTextModule()
    nonisolated static let removeLineBreaksKey = "screenText.removeLineBreaks"
    var removeLineBreaks = false
}
extension LiveTimerModule { static let shared = LiveTimerModule() }
extension DayMarketsModule { static let shared = DayMarketsModule() }
extension DayWeatherModule { static let shared = DayWeatherModule() }
extension QuitProtectionStore { static let shared = QuitProtectionStore() }
extension DictationCleanupModule {
    static let shared = DictationCleanupModule(
        store: .live(bundleIdentifier: Bundle.main.bundleIdentifier!)!, install: { }, uninstall: { })
}
extension ForkSettingsBackupCoordinator { static let shared = ForkSettingsBackupCoordinator() }
@MainActor final class EditorCoordinator {
    static let shared = EditorCoordinator()
    let editorPreferences = EditorPreferences(defaults: UserDefaults(suiteName: Bundle.main.bundleIdentifier! + ".editor")!)
}
@MainActor final class AppearanceThemeColors {
    static let shared = AppearanceThemeColors()
    func update(light: RaycastTheme?, dark: RaycastTheme?, preview: RaycastThemeLink.Target?, opacity: Double) { }
}

@MainActor final class DialogScript {
    var calls = 0
    var continuation: CheckedContinuation<Bool, Never>?
    func confirm() async -> Bool {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func answer(_ answer: Bool) { continuation?.resume(returning: answer); continuation = nil }
    func waitForDialog() async {
        while continuation == nil { await Task.yield() }
    }
}
