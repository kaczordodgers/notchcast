// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule+Command.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
import AppKit
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift

@MainActor final class CaptureAreaService {
    func start(completion: @escaping (CaptureAreaSelection?) -> Void) throws {}
    func stop() {}
}

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

extension ScreenshotModule {
    static var instance: ScreenshotModule?
    static var shared: ScreenshotModule { instance! }
}

@MainActor final class NSScreen {
    static var underCursor: NSScreen? = NSScreen()
    let displayID: UInt32? = 42
}

enum DialogTone { case danger }

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
        var messages: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
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
        ScreenshotModule.instance = module
        let controller = NotchcastModuleController([
            .init(requires: [.screenshot], module: module)
        ], preferences: preferences)
        controller.run()
        let command = ScreenshotModule.launcherCommand
        preferences.set(.screenshot, true)
        await settle()
        command.run()
        await module.commandTask?.value
        precondition(calls == 1 && messages.isEmpty)
        shouldFail = true
        command.run()
        await module.commandTask?.value
        precondition(calls == 2 && messages == [String(localized: "Screen Recording access is required.")])
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
        ScreenshotModule.instance = nil
        precondition(ScreenshotModule.failureMessage(ScreenshotRequest.Failure.clipboardFailed)
                     == String(localized: "Could not copy to clipboard."))
        precondition(ScreenshotModule.failureMessage(NSError(domain: "com.apple.ScreenCaptureKit", code: -3802))
                     == String(localized: "Could not capture the screen."))
        precondition(ScreenshotModule.failureMessage(CocoaError(.fileWriteNoPermission))
                     == String(localized: "Could not save the screenshot."))
        for denied in [CaptureFailure.permissionDenied, ScreenshotRequest.Failure.permissionDenied] as [any Error] {
            precondition(ScreenshotModule.failureMessage(denied) == String(localized: "Screen Recording access is required."))
        }
        precondition(ScreenshotModule.failureMessage(ScreenshotRequest.Failure.disabled)
                     == String(localized: "Capture is disabled."))
        precondition(ScreenshotModule.failureMessage(ScreenshotRequest.Failure.invalidRect)
                     == String(localized: "Capture area is unavailable."))
        print("PASS: screenshot module command, display selection, switch lifecycle and failure HUD")
    }

    @MainActor private static func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }
}
