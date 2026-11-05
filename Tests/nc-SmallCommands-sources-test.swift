// notchcast-sources: Tinycast/Features/Launcher/SmallCommands/Model/*.swift Tinycast/Features/Launcher/SmallCommands/Service/*.swift Tinycast/Features/Launcher/SmallCommands/SmallCommandsModule*.swift
// notchcast-sources: Tinycast/Features/Launcher/CopyPath/Model/*.swift Tinycast/Features/Launcher/CopyPath/Service/*.swift Tinycast/Platform/AccessibilityText.swift
import Foundation

@MainActor protocol NotchcastModule {}
enum NotchcastFeature { case smallCommands }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor enum NotchcastCore { static let smallCommands = SmallCommandsModule() }
@MainActor final class AppCore {
    enum Tone { case neutral }
    static let shared = AppCore()
    func showMessage(_ text: String, tone: Tone) { preconditionFailure("Unexpected HUD") }
}
@main struct SourceTests {
    @MainActor static func main() async throws {
        let module = SmallCommandsModule()
        module.start()
        defer { module.stop() }
        for source in ["https://example.com/browser", "Read https://example.com/selection", "invalid", ""] {
            let expected = source.contains("browser") ? "https://example.com/browser"
                : source.contains("selection") ? "https://example.com/selection" : "https://example.com/clipboard"
            let service = ShortenLinkService { request in
                let actual = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                    .queryItems!.first!.value!
                guard actual == expected else {
                    FileHandle.standardError.write(Data("FAIL: expected \(expected), got \(actual)\n".utf8))
                    exit(1)
                }
                return (Data("https://tinyurl.com/fake".utf8), 200)
            }
            let result = try await module.perform(.shorten, frontAddress: { source },
                clipboard: { "https://example.com/clipboard" }, service: service)
            precondition(result == "https://tinyurl.com/fake")
        }
        print("PASS: front browser/selection precedes clipboard; missing or invalid source falls back")
    }
}
