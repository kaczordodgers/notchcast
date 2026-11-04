// notchcast-sources: Tinycast/Features/VoiceAsk/Model/*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
import Foundation

@MainActor
final class FakeTransport: VoiceAskTransport {
    var texts: [String] = []
    func send(_ text: String, destination: String) async throws -> VoiceAskResult {
        texts.append(text)
        return VoiceAskResult(state: .completed, firstLines: [destination])
    }
}

@main
struct Tests {
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
        print("PASS: hold transitions, fake delivery, switch lifecycle, default off")
    }
}
