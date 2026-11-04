// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/QuickLookCoordinator.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/QuickLookSpaceInput.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/QuickLookSystemPresenter.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Model/QuickLookRequest.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Model/QuickLookSpacePolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

@main
struct QuickLookHookTests {
    @MainActor
    static func main() {
        let suite = "nc-space-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.quickLookSpace, true)
        let coordinator = QuickLookCoordinator(preferences: preferences)
        let input = coordinator.spaceInput
        let url = URL(fileURLWithPath: "/tmp/example.md")
        var screen = UUID()
        var calls: [String] = []
        func key(arrow: Bool = false, space: Bool = false, reset: Bool = false,
                 modifiers: Bool = false, composing: Bool = false, repeats: Bool = false) -> Bool {
            input.handle(
                screen: screen, arrow: arrow, space: space, resetsSelection: reset,
                fileURL: url, hasModifiers: modifiers, isRepeat: repeats, isComposing: composing,
                coordinator: coordinator, dismiss: { calls.append("dismiss") },
                present: { request in
                    precondition(request.fileURL == url)
                    precondition(coordinator.request == request)
                    calls.append("present")
                })
        }
        precondition(!key(space: true))
        precondition(!key(arrow: true))
        precondition(!key(space: true, modifiers: true))
        precondition(!key(space: true, composing: true))
        precondition(!key(space: true, repeats: true))
        precondition(key(space: true))
        precondition(calls == ["dismiss", "present"])
        calls.removeAll()
        precondition(!key(reset: true))
        precondition(!key(space: true))
        precondition(!key(arrow: true))
        screen = UUID()
        precondition(!key(space: true))
        precondition(!key(arrow: true))
        preferences.set(.quickLookSpace, false)
        precondition(!key(space: true))
        precondition(calls.isEmpty)
        print("PASS: arrow then Space reaches engine and fake presenter after dismissal")
        print("PASS: typing, pointer reset, screen reset, modifiers, IME, repeat and disabled gates")
    }
}
