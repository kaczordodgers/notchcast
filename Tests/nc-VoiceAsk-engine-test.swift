// notchcast-sources: Tinycast/Features/VoiceAsk/Model/*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
import Foundation

enum DialogTone { case success, danger }

@MainActor
final class FakeTransport: VoiceAskTransport {
    var texts: [String] = []
    var gate: Gate?
    func send(_ text: String, destination: String) async throws -> VoiceAskResult {
        texts.append(text)
        if let gate { await gate.wait() }
        return VoiceAskResult(state: .completed, firstLines: [destination])
    }
}

@MainActor
final class Gate {
    var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@main
struct Tests {
    @MainActor
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Timed out waiting for recording or delivery")
    }

    @MainActor
    static func main() async throws {
        var hold = VoiceAskHold()
        hold.press(alone: true)
        precondition(hold.state == .pending)
        precondition(hold.release() == .none)
        hold.press(alone: true)
        precondition(hold.threshold() == .begin)
        precondition(hold.chord() == .cancel)
        precondition(hold.release() == .none)
        hold.press(alone: false)
        precondition(hold.threshold() == .none)
        precondition(hold.release() == .none)
        hold.press(alone: true)
        precondition(hold.threshold() == .begin)
        precondition(hold.release() == .finish)

        let suite = "voice-ask-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.voiceAsk))
        var starts = 0
        let module = VoiceAskModule(defaults: defaults, begin: { starts += 1 },
                                    finish: { "hello" }, cancel: {})
        let fake = FakeTransport()
        module.configure(transport: fake)
        module.destination = "fixture"
        let controller = NotchcastModuleController([
            .init(requires: [.voiceAsk], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!module.enabled)
        preferences.set(.voiceAsk, true)
        try await Task.sleep(for: .milliseconds(100))
        precondition(module.enabled)
        module.press(alone: true)
        try await Task.sleep(for: .milliseconds(300))
        precondition(starts == 1)
        module.release()
        try await Task.sleep(for: .milliseconds(100))
        precondition(fake.texts == ["hello"])
        precondition(module.result?.firstLines == ["fixture"])
        preferences.set(.voiceAsk, false)
        try await Task.sleep(for: .milliseconds(100))
        precondition(!module.enabled)
        module.press(alone: true)
        try await Task.sleep(for: .milliseconds(300))
        precondition(starts == 1)
        try await idleChords(defaults: defaults)
        try await clearsFailure(defaults: defaults)
        print("PASS: hold transitions, fake delivery, switch lifecycle, default off")
    }

    @MainActor
    static func idleChords(defaults: UserDefaults) async throws {
        let startup = Gate()
        let transcription = Gate()
        let sending = Gate()
        var capturing = false
        var finishes = 0
        let module = VoiceAskModule(defaults: defaults, begin: {
            capturing = true
            await startup.wait()
        }, finish: {
            finishes += 1
            capturing = false
            await transcription.wait()
            return "held ask"
        }, cancel: { capturing = false })
        let transport = FakeTransport()
        transport.gate = sending
        module.configure(transport: transport)
        module.destination = "fixture"
        module.start()
        module.press(alone: true)
        try await waitUntil { startup.continuation != nil }
        module.release()
        module.chord()
        startup.resume()
        try await waitUntil { transcription.continuation != nil }
        precondition(finishes == 1 && !capturing, "Release must close capture after delayed startup")
        module.chord()
        module.press(alone: true)
        module.release()
        transcription.resume()
        try await waitUntil { sending.continuation != nil }
        precondition(transport.texts == ["held ask"], "Typing during transcription must preserve delivery")
        module.chord()
        module.press(alone: true)
        module.release()
        sending.resume()
        try await waitUntil { module.result != nil }
        precondition(module.result?.firstLines == ["fixture"] && module.failure == nil)
        module.stop()
        print("PASS: idle chords preserve delayed startup cleanup, transcription and send")
    }

    @MainActor
    static func clearsFailure(defaults: UserDefaults) async throws {
        let module = VoiceAskModule(defaults: defaults, begin: {
            throw CocoaError(.fileReadUnknown)
        }, finish: { "" }, cancel: {})
        module.configure(transport: FakeTransport())
        module.destination = "fixture"
        module.start()
        module.press(alone: true)
        try await waitUntil { module.failure != nil }
        module.press(alone: true)
        precondition(module.failure == nil, "A new press must clear the previous failure")
        module.stop()
        print("PASS: next press clears failure")
    }
}
