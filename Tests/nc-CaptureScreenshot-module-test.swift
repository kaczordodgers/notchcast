// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
import AppKit

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor enum NotchcastCore {
    static var instance: ScreenshotModule?
    static var screenshot: ScreenshotModule { instance! }
}

@MainActor final class NSScreen {
    static var underCursor: NSScreen? = NSScreen()
    let deviceDescription = [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: 42)]
}

@MainActor final class AppCore {
    enum Tone { case danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ message: String, tone: Tone) { messages.append(message) }
}

@MainActor enum ScreenshotService {
    static func capture(
        _ request: ScreenshotRequest, destination: ScreenshotRequest.Destination,
        isEnabled: @MainActor () -> Bool
    ) async throws -> URL? {
        preconditionFailure("Harness must inject capture")
    }
}

@main
struct ScreenshotModuleTest {
    @MainActor static func main() async {
        let suite = "screenshot-module-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.screenshot, false)
        var calls = 0
        var shouldFail = false
        let module = ScreenshotModule(defaults: defaults, capture: { request, _, isEnabled in
            precondition(isEnabled())
            guard case .display(42) = request else { preconditionFailure("Wrong display") }
            calls += 1
            if shouldFail { throw ScreenshotRequest.Failure.permissionDenied }
            return nil
        })
        NotchcastCore.instance = module
        let controller = NotchcastModuleController([
            .init(requires: [.screenshot], module: module)
        ], preferences: preferences)
        controller.run()
        let command = ScreenshotModule.launcherCommand
        precondition(command.slug == "screenshot-display")
        preferences.set(.screenshot, true)
        await settle()
        command.run()
        await module.commandTask?.value
        precondition(calls == 1 && AppCore.shared.messages.isEmpty)
        shouldFail = true
        command.run()
        await module.commandTask?.value
        precondition(calls == 2 && AppCore.shared.messages == [String(localized: "Capture Screen")])
        preferences.set(.screenshot, false)
        await settle()
        precondition(module.commandTask == nil)
        do {
            _ = try await module.capture(.display(42))
            preconditionFailure("Disabled capture ran")
        } catch ScreenshotRequest.Failure.disabled {} catch { preconditionFailure("Wrong error") }
        precondition(calls == 2)
        NSScreen.underCursor = nil
        command.run()
        precondition(module.commandTask == nil)
        NotchcastCore.instance = nil
        print("PASS: screenshot module command, display selection, switch lifecycle and failure HUD")
    }

    @MainActor private static func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }
}
