// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/Service/*.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/EditorCoordinator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteDocument.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteEditAction.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteEditPlan.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteFormatting.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdown.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdownEditing.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdownParser.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteInlineScanner.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteTitle.swift
import AppKit

@main
@MainActor
struct EditorCoordinatorTests {
    static func main() async throws {
        let suite = "app.notchcast.test.editor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.markdownFiles, true) // hidden switches read off until set
        preferences.set(.plainTextFiles, true)
        let coordinator = EditorCoordinator(preferences: preferences, editorPreferences: EditorPreferences(defaults: defaults))
        defer { coordinator.stop() }
        let url = directory.appendingPathComponent("document.md")
        try Data("# Markdown".utf8).write(to: url)
        do {
            _ = try await coordinator.open(url)
            preconditionFailure("stopped module must reject opens")
        } catch EditorFailure.disabled {}
        coordinator.start()
        async let firstOpen = coordinator.open(url)
        async let secondOpen = coordinator.open(url)
        let (first, second) = try await (firstOpen, secondOpen)
        precondition(first === second && coordinator.documents.count == 1)
        precondition(first.rendersMarkdown)
        let alias = directory.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url)
        let aliased = try await coordinator.open(alias)
        precondition(aliased === first)
        precondition(first.edit("draft"))
        do {
            try coordinator.close(first)
            preconditionFailure("closing a dirty document must require an explicit discard")
        } catch EditorFailure.unsavedChanges {}
        preferences.set(.markdownFiles, false)
        while first.isEnabled { await Task.yield() }
        precondition(!first.isEnabled && first.source == "draft")
        do {
            _ = try await coordinator.open(url)
            preconditionFailure("disabled file type must reject opens")
        } catch EditorFailure.disabled {}
        try coordinator.close(first, discardChanges: true)
        precondition(coordinator.documents.isEmpty)
        let plain = directory.appendingPathComponent("document.txt")
        try Data("plain\r\ntext".utf8).write(to: plain)
        let document = try await coordinator.open(plain)
        precondition(!document.rendersMarkdown && document.source == "plain\r\ntext")
        let created = try await coordinator.newDocument(at: directory.appendingPathComponent("new.txt"))
        precondition(created.source.isEmpty && !created.isDirty)
        try coordinator.close(created)
        do {
            try await coordinator.saveAs(document, to: directory.appendingPathComponent("blocked.md"))
            preconditionFailure("Save As must respect the destination feature switch")
        } catch EditorFailure.disabled {}
        preferences.set(.markdownFiles, true)
        let cancelled = Task { try await coordinator.open(url) }
        cancelled.cancel()
        _ = await cancelled.result
        precondition(coordinator.documents.count == 1)
        precondition(NotchcastFeature.markdownFiles.settingsGroup == .system)
        precondition(!NotchcastFeature.markdownFiles.needsIsland)
        precondition(!NotchcastFeature.plainTextFiles.needsIsland)
        print("Editor coordinator: lifecycle, type switches, identity, spelling and dirty-close protection passed")
    }
}
