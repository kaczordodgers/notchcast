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
        scrolling.capture { message, tone in
            precondition(tone == .danger)
            messages.append(message)
        }
        precondition(requests == 0)
        var refreshed = 0
        var availabilityChanges = 0
        preferences.commandAvailabilityChanged = { availabilityChanges += 1 }
        preferences.set(.katana, !preferences.isOn(.katana))
        precondition(availabilityChanges == 1)
        print("PASS: Katana switch refreshes production command availability")
        preferences.onCommandsChanged = { refreshed += 1 }
        preferences.set(.screenText, true)
        preferences.set(.scrollingCapture, true)
        preferences.set(.island, false)
        await settle()
        precondition(requests == 0)
        text.capture { messages.append($0) }
        scrolling.capture { message, tone in
            precondition(tone == .danger)
            messages.append(message)
        }
        precondition(requests == 2 && messages.count == 2 && refreshed == 3)
        preferences.set(.screenText, false)
        preferences.set(.scrollingCapture, false)
        await settle()
        text.capture { messages.append($0) }
        scrolling.capture { message, _ in messages.append(message) }
        precondition(requests == 2)
        text.removeLineBreaks = true
        precondition(ScreenTextModule(defaults: defaults).removeLineBreaks)
        for feature in [NotchcastFeature.screenText, .scrollingCapture] {
            precondition(!feature.needsIsland && feature.requiredGrants == [.screenRecording])
        }
        precondition(ScreenTextModule.failureMessage(ScreenTextService.Failure.noContent)
                     != ScreenTextModule.failureMessage(ScreenTextService.Failure.clipboardWriteFailed))
        await testInFlightStop(defaults: defaults)
        print("PASS: OCR/scroll switches start and stop, no startup prompts, independent of Island, persisted OCR option")
    }

    private static func testInFlightStop(defaults: UserDefaults) async {
        let selection = CaptureAreaSelection(
            rect: CGRect(x: 0, y: 0, width: 10, height: 10), displayID: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        func area() -> CaptureAreaService {
            CaptureAreaService(hasScreenRecordingAccess: { true }, select: { $0(selection) })
        }
        let recognition = Suspension()
        var writes = 0
        var reports = 0
        let text = ScreenTextModule(defaults: defaults, area: area(), recognize: { _, _ in
            await recognition.wait()
            return ScreenTextResult(content: "Late text", kind: .text)
        }, write: { _ in writes += 1; return true })
        text.start()
        text.capture { _ in reports += 1 }
        while !recognition.started { await Task.yield() }
        text.stop()
        recognition.resume()
        await settle()
        precondition(writes == 0 && reports == 0)

        let frame = Suspension()
        let session = ScrollingCaptureSession(prepareCapture: { _, _, _ in
            return {
                await frame.wait()
                throw ScrollingCaptureSession.Failure.invalidFrame
            }
        }, requestAccess: { true })
        let scrolling = ScrollingCaptureModule(area: area(), session: session,
                                               write: { _ in writes += 1; return true })
        scrolling.start()
        scrolling.capture { _, tone in
            precondition(tone == .neutral)
            reports += 1
        }
        while !frame.started { await Task.yield() }
        precondition(reports == 1 && session.state == .capturing)
        scrolling.stop()
        frame.resume()
        await settle()
        precondition(session.state == .idle && writes == 0 && reports == 1)
        print("PASS: neutral scrolling prompt; switch-off cancels in-flight OCR and scrolling without late output")
    }

    @MainActor
    private final class Suspension {
        var started = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation {
                continuation = $0
                started = true
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}
