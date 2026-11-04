// notchcast-sources: Tinycast/Features/DictationEnglish/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationEnglish/Service/DictationEnglish.swift
// notchcast-sources: Tinycast/Features/DictationEnglish/Service/DictationEnglishModule.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Service/DictationCleanup.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Service/DictationCleanupClient.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Service/DictationCleanupSettingsStore.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

private struct FakeClient: DictationCleanupClient {
    var output = "Send Claude the report."
    var fails = false
    var delay: Duration = .zero

    func clean(_ request: URLRequest) async throws -> String {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        precondition((body?["model"] as? String)?.contains("sonnet") == true)
        precondition((body?["system"] as? String)?.contains("output English only") == true)
        if fails { throw URLError(.cannotConnectToHost) }
        try await Task.sleep(for: delay)
        return output
    }
}

@main
struct EnglishTests {
    @MainActor
    static func main() async {
        let settings = DictationCleanupSettings()
        let prompt = DictationEnglishPrompt.system(settings: settings, language: "Polish")
        precondition(!prompt.contains("never translate"))
        precondition(prompt.contains("technical terms unchanged"))
        let raw = "Wyślij Claude raport."
        let result = await DictationEnglish.process(raw, language: "Polish", settings: settings,
                                                    key: "fixture", client: FakeClient())
        precondition(result == "Send Claude the report.")
        for client in [FakeClient(output: ""), FakeClient(fails: true),
                       FakeClient(delay: .seconds(1))] {
            let fallback = await DictationEnglish.process(raw, language: nil, settings: settings,
                key: "fixture", client: client, timeout: .milliseconds(10))
            precondition(fallback == raw)
        }
        var callback: (@MainActor () -> Void)?
        var registrations = 0
        var removals = 0
        var toggles = 0
        let module = DictationEnglishModule(register: {
            registrations += 1
            callback = $0
            return UUID()
        }, remove: { _ in removals += 1 }, toggle: { toggles += 1 })
        module.start()
        module.start()
        callback?()
        precondition(registrations == 1 && toggles == 1)
        module.stop()
        callback?()
        module.stop()
        precondition(removals == 1 && toggles == 1)
        module.start()
        precondition(registrations == 2)
        module.stop()
        print("English dictation: prompt, Sonnet, cleanup-off, fallback, timeout and lifecycle passed")
    }
}
