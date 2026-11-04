// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Model/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Service/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/ScreenTextModule.swift
// notchcast-sources: Tinycast/Features/CaptureScrolling/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureScrolling/Service/*.swift
// notchcast-sources: Tinycast/Features/CaptureScrolling/ScrollingCaptureModule.swift
import Foundation

@main @MainActor
struct CaptureWiringTest {
    static func main() async {
        let suite = "capture-wiring-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.screenText, false)
        preferences.set(.scrollingCapture, false)
        var requests = 0
        var messages: [String] = []
        func area() -> CaptureAreaService {
            CaptureAreaService(hasScreenRecordingAccess: { false }, requestScreenRecordingAccess: {
                requests += 1
                return false
            })
        }
        let text = ScreenTextModule(defaults: defaults, area: area(), recognize: { _, _ in
            fatalError("Permission denied must never reach recognition")
        }, write: { _ in fatalError("Unexpected clipboard write") })
        let scrolling = ScrollingCaptureModule(area: area(), session: ScrollingCaptureSession(
            requestAccess: { fatalError("Permission denied must never start scrolling") }),
            write: { _ in fatalError("Unexpected clipboard write") })
        let controller = NotchcastModuleController([
            .init(requires: [.screenText], module: text),
            .init(requires: [.scrollingCapture], module: scrolling)
        ], preferences: preferences)
        controller.run()
        text.capture { messages.append($0) }
        scrolling.capture { messages.append($0) }
        precondition(requests == 0)
        var refreshed = 0
        preferences.onCommandsChanged = { refreshed += 1 }
        preferences.set(.screenText, true)
        preferences.set(.scrollingCapture, true)
        preferences.set(.island, false)
        await settle()
        precondition(requests == 0)
        text.capture { messages.append($0) }
        scrolling.capture { messages.append($0) }
        precondition(requests == 2 && messages.count == 2 && refreshed == 3)
        preferences.set(.screenText, false)
        preferences.set(.scrollingCapture, false)
        await settle()
        text.capture { messages.append($0) }
        scrolling.capture { messages.append($0) }
        precondition(requests == 2)
        text.removeLineBreaks = true
        precondition(ScreenTextModule(defaults: defaults).removeLineBreaks)
        for feature in [NotchcastFeature.screenText, .scrollingCapture] {
            precondition(!feature.needsIsland && feature.requiredGrants == [.screenRecording])
        }
        precondition(ScreenTextModule.failureMessage(ScreenTextService.Failure.noContent)
                     != ScreenTextModule.failureMessage(ScreenTextService.Failure.clipboardWriteFailed))
        print("PASS: OCR/scroll switches start and stop, no startup prompts, independent of Island, persisted OCR option")
    }

    private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}
