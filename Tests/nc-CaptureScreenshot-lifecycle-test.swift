// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Service/*.swift
import Foundation
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift

@MainActor
private final class CaptureProbe {
    var calls = 0
    var outputs = 0
    var destination: ScreenshotRequest.Destination?
    var pending: CheckedContinuation<Void, Never>?

    func capture(
        _ request: ScreenshotRequest, destination: ScreenshotRequest.Destination,
        isEnabled: @MainActor () -> Bool
    ) async throws -> URL? {
        guard isEnabled() else { throw ScreenshotRequest.Failure.disabled }
        guard case .rect(let rect) = request, rect == CGRect(x: -80, y: 40, width: 60, height: 30) else {
            preconditionFailure("Quartz rect must pass through unchanged")
        }
        calls += 1
        self.destination = destination
        await withCheckedContinuation { pending = $0 }
        try Task.checkCancellation()
        guard isEnabled() else { throw ScreenshotRequest.Failure.disabled }
        outputs += 1
        return nil
    }

    func finish() {
        precondition(pending != nil)
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}

@main
struct ScreenshotLifecycleTest {
    @MainActor
    static func main() async throws {
        let suite = "screenshot-lifecycle-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.screenshot, false)
        let probe = CaptureProbe()
        let module = ScreenshotModule(defaults: defaults, capture: probe.capture)
        let controller = NotchcastModuleController([
            .init(requires: [.screenshot], module: module)
        ], preferences: preferences)
        controller.run()
        let rect = ScreenshotRequest.rect(CGRect(x: -80, y: 40, width: 60, height: 30))
        do {
            _ = try await module.capture(rect)
            preconditionFailure("Disabled capture started")
        } catch ScreenshotRequest.Failure.disabled {}
        precondition(probe.calls == 0 && module.destination == .clipboard && module.folder == nil)
        precondition(!NotchcastFeature.screenshot.needsIsland)
        precondition(NotchcastFeature.screenshot.requiredGrants == [.screenRecording])

        preferences.set(.screenshot, true)
        preferences.set(.island, false)
        await settle()
        let first = Task { try await module.capture(rect) }
        await settle()
        precondition(probe.calls == 1)
        preferences.set(.screenshot, false)
        await settle()
        probe.finish()
        await expectCancellation(first)
        precondition(probe.outputs == 0)

        preferences.set(.screenshot, true)
        await settle()
        let second = Task { try await module.capture(rect) }
        await settle()
        module.destination = .both
        probe.finish()
        await expectCancellation(second)
        precondition(probe.outputs == 0)

        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        module.folder = folder
        let restored = ScreenshotModule(defaults: defaults)
        precondition(restored.destination == .both && restored.folder == folder)
        let third = Task { try await module.capture(rect) }
        await settle()
        guard case .both(let selected) = probe.destination else { preconditionFailure("Wrong output") }
        precondition(selected == folder)
        preferences.set(.islandStatusMessages, false)
        await settle()
        probe.finish()
        _ = try await third.value
        precondition(probe.outputs == 1)

        let fourth = Task { try await module.capture(rect) }
        await settle()
        fourth.cancel()
        await settle()
        probe.finish()
        await expectCancellation(fourth)

        let fifth = Task { try await module.capture(rect) }
        await settle()
        module.folder = folder.appending(path: "other")
        probe.finish()
        await expectCancellation(fifth)
        precondition(probe.calls == 5 && probe.outputs == 1)
        module.stop()
        print("PASS: screenshot switch starts/stops capture; destination and caller cancellation stop output")
    }

    @MainActor
    private static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private static func expectCancellation(_ task: Task<URL?, Error>) async {
        do {
            _ = try await task.value
            preconditionFailure("Cancelled capture completed")
        } catch is CancellationError {} catch {
            preconditionFailure("Unexpected capture error: \(error)")
        }
    }
}
