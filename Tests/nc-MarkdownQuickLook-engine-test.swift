// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Model/*.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdown.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdownParser.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteInlineScanner.swift
import Foundation

@main
struct MarkdownQuickLookTests {
    static func check(_ condition: Bool) { precondition(condition) }

    @MainActor
    static func main() async throws {
        let suite = "nc-quicklook-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let coordinator = QuickLookCoordinator(preferences: preferences)
        let url = URL(fileURLWithPath: "/temporary/sample.md")
        let enabled = preferences.isOn(.quickLookSpace)
        precondition(enabled && !NotchcastFeature.quickLookSpace.needsIsland)
        precondition(NotchcastFeature.quickLookSpace.settingsGroup == .launcher)
        precondition(NotchcastFeature.quickLookSpace.requiredGrants.isEmpty)

        for selected in [false, true] {
            for modifiers in [false, true] {
                for repeats in [false, true] {
                    for composing in [false, true] {
                        var dismissed = false
                        let handled = coordinator.previewOnSpace(
                            fileURL: url, selectedByArrowKeys: selected, hasModifiers: modifiers,
                            isRepeat: repeats, isComposing: composing,
                            dismissLauncher: {
                                precondition(coordinator.request == nil)
                                dismissed = true
                            })
                        let expected = selected && !modifiers && !repeats && !composing
                        precondition(handled == expected)
                        precondition(dismissed == expected)
                        precondition(coordinator.request?.fileURL == (expected ? url : nil))
                        coordinator.stop()
                    }
                }
            }
        }
        for invalid in [nil, URL(string: "https://example.invalid/file.md")] {
            precondition(!coordinator.previewOnSpace(
                fileURL: invalid, selectedByArrowKeys: true,
                dismissLauncher: { preconditionFailure("Invalid item dismissed the launcher") }))
        }
        preferences.set(.quickLookSpace, false)
        precondition(!NotchcastPreferences(suiteName: suite).isOn(.quickLookSpace))
        precondition(!coordinator.previewOnSpace(
            fileURL: url, selectedByArrowKeys: true,
            dismissLauncher: { preconditionFailure("Disabled feature dismissed the launcher") }))
        coordinator.stop()
        precondition(coordinator.request == nil)
        preferences.set(.quickLookSpace, true)
        coordinator.previewOnSpace(fileURL: url, selectedByArrowKeys: true, dismissLauncher: {})
        let first = coordinator.request!.id
        coordinator.previewOnSpace(fileURL: url, selectedByArrowKeys: true, dismissLauncher: {})
        let second = coordinator.request!.id
        precondition(first != second)
        coordinator.dismissPreview(first)
        precondition(coordinator.request?.id == second)
        coordinator.dismissPreview(second)
        precondition(coordinator.request == nil)
        coordinator.previewOnSpace(fileURL: url, selectedByArrowKeys: true, dismissLauncher: {})
        coordinator.stop()
        precondition(coordinator.request == nil)
        coordinator.previewOnSpace(
            fileURL: url, selectedByArrowKeys: true,
            dismissLauncher: { preferences.set(.quickLookSpace, false) })
        precondition(coordinator.request == nil)
        print("Space: typed spaces, modifiers, repeats, composition, invalid items and disabled switch pass")
        print("Requests: dismissal ordering, teardown, persisted preference and stale dismissal pass")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.md")
        let source = "# Heading\n\n**Bold** [safe](https://example.invalid)\n- [x] Done\n```swift\nlet x = 1\n```\n"
        try Data(("\u{FEFF}" + source).utf8).write(to: file)
        let document = try await MarkdownQuickLookReader.read(file)
        precondition(document.source == source)
        precondition(document.markdown.lines.first?.kind == .heading(level: 1))
        precondition(document.markdown.lines.contains { $0.kind == .task(checked: true) })
        precondition(document.markdown.lines.contains { $0.kind == .code })
        check(try Data(contentsOf: file) == Data(("\u{FEFF}" + source).utf8))
        try Data().write(to: file)
        let empty = try await MarkdownQuickLookReader.read(file)
        precondition(empty.source.isEmpty)
        try Data([0xFF, 0xFE, 0xFF]).write(to: file)
        do {
            _ = try await MarkdownQuickLookReader.read(file)
            preconditionFailure("Invalid UTF-8 was accepted")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadInapplicableStringEncoding)
        }
        let limit = MarkdownQuickLookDocument.maximumBytes
        let exact = try MarkdownQuickLookDocument(data: Data(repeating: 65, count: limit))
        precondition(exact.source.utf8.count == limit)
        try Data(repeating: 65, count: limit + 1).write(to: file)
        do {
            _ = try await MarkdownQuickLookReader.read(file)
            preconditionFailure("Oversized document was accepted")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadTooLarge)
        }
        do {
            _ = try await MarkdownQuickLookReader.read(root.appendingPathComponent("missing.md"))
            preconditionFailure("Missing file was accepted")
        } catch is CocoaError {}
        do {
            _ = try await MarkdownQuickLookReader.read(root)
            preconditionFailure("Directory was accepted")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadUnknown)
        }
        do {
            _ = try await MarkdownQuickLookReader.read(URL(string: "https://example.invalid/file.md")!)
            preconditionFailure("Remote document was accepted")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadUnsupportedScheme)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MarkdownQuickLookReader.read(file)
        }
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled read completed")
        } catch is CancellationError {}
        print("Reader: Markdown, BOM, empty, invalid UTF-8, exact limit, oversize, missing and remote pass")
        print("Reader: cancellation propagates; source file remains unchanged")
    }
}
