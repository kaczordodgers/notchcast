// notchcast-sources: Tinycast/Features/VoiceAsk/Model/*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskModule.swift
// notchcast-kit: core

import Foundation

enum DialogTone { case success, danger }

@MainActor
final class ModuleTransport: VoiceAskTransport {
    var calls = 0
    var fails = false
    func send(_ text: String, destination: String) async throws -> VoiceAskResult {
        precondition(text == "fixture question" && destination == "fixture")
        calls += 1
        if fails { throw NSError(domain: "fixture", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "Fake delivery failed"]) }
        return VoiceAskResult(state: .completed, firstLines: ["fixture answer"])
    }
}

@main
struct VoiceAskModuleTest {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Module transition timed out")
    }

    @MainActor static func main() async throws {
        let suite = "voice-module-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var begins = 0
        var starts = 0
        var stops = 0
        var cancels = 0
        var messages: [(String, DialogTone)] = []
        let module = VoiceAskModule(defaults: defaults, begin: { begins += 1 },
                                    finish: { "fixture question" }, cancel: { cancels += 1 },
                                    message: { messages.append(($0, $1)) })
        module.onStart = { starts += 1 }
        module.onStop = { stops += 1 }
        let transport = ModuleTransport()
        module.configure(transport: transport)
        module.destination = "fixture"
        let controller = NotchcastModuleController([
            .init(requires: [.voiceAsk], module: module)], preferences: preferences)
        controller.run()
        precondition(!module.enabled)
        preferences.set(.voiceAsk, true)
        try await wait { module.enabled }
        precondition(starts == 1)
        module.press(alone: true)
        try await wait { begins == 1 }
        module.release()
        try await wait { module.result != nil }
        precondition(transport.calls == 1 && module.result?.firstLines == ["fixture answer"])
        precondition(messages.count == 1 && messages[0].0 == "fixture answer" && messages[0].1 == .success)
        transport.fails = true
        module.press(alone: true)
        try await wait { begins == 2 }
        module.release()
        try await wait { module.failure != nil }
        precondition(module.failure == "Fake delivery failed" && transport.calls == 2)
        precondition(messages.count == 2 && messages[1].0 == "Fake delivery failed" && messages[1].1 == .danger)
        let previousCancels = cancels
        preferences.set(.voiceAsk, false)
        try await wait { !module.enabled }
        precondition(stops == 1 && cancels > previousCancels)
        module.press(alone: true)
        try await Task.sleep(for: .milliseconds(300))
        module.release()
        precondition(begins == 2 && transport.calls == 2)
        print("PASS: switch callbacks, fake recording and delivery, visible failure, disabled input")
    }
}
