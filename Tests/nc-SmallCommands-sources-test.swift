// notchcast-sources: Tinycast/Features/SmallCommands/Model/*.swift Tinycast/Features/SmallCommands/Service/*.swift
// notchcast-sources: Tinycast/Features/SmallCommands/SmallCommandsModule.swift
// notchcast-sources: Tinycast/Features/SmallCommands/SmallCommandsModule+Commands.swift
// notchcast-sources: Tinycast/Features/CopyPath/Model/*.swift Tinycast/Features/CopyPath/Service/*.swift Tinycast/Platform/AccessibilityText.swift
// notchcast-kit: host
import Foundation

@MainActor protocol NotchcastModule {}
enum DialogTone { case neutral }
enum NotchcastFeature { case smallCommands }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    var argumentCount = 0
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
    var id: String { "command:nc-" + slug }
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
extension SmallCommandsModule { static let shared = SmallCommandsModule() }
@main struct SourceTests {
    @MainActor static func main() async throws {
        NotchcastHost.current.showMessage = { _, _ in preconditionFailure("Unexpected HUD") }
        let module = SmallCommandsModule()
        module.start()
        defer { module.stop() }
        for argument in ["", "https://example.com/typed"] {
            for source in ["https://example.com/browser", "Read https://example.com/selection", "invalid", ""] {
                let expected = !argument.isEmpty ? argument : source.contains("browser") ? "https://example.com/browser"
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
                let result = try await module.perform(.shorten, argument: argument, frontAddress: { source },
                    clipboard: { "https://example.com/clipboard" }, service: service)
                precondition(result == "https://tinyurl.com/fake")
            }
        }
        print("PASS: typed argument wins; empty argument uses front browser/selection then clipboard")
    }
}
