// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/Service/*.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/EditorCoordinator.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/EditorOpenPanel.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/EditorCoordinator+Command.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteDocument.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteEditAction.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteEditPlan.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteFormatting.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdown*.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteInlineScanner.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteTitle.swift
import Foundation

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor
enum NotchcastCore {
    static var editor: EditorCoordinator!
}

@main
@MainActor
struct EditorOpenTests {
    static func main() async throws {
        let suite = "app.notchcast.test.editor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("open.md")
        try Data("hello".utf8).write(to: url)
        var selection: URL?
        var panels = 0
        var refreshes = 0
        var failures = 0
        let coordinator = EditorCoordinator(preferences: preferences,
            editorPreferences: EditorPreferences(defaults: defaults), selectFile: {
                panels += 1
                return selection
            })
        coordinator.refreshCommands = { refreshes += 1 }
        coordinator.reportOpenFailure = { _ in failures += 1 }
        NotchcastCore.editor = coordinator
        let command = EditorCoordinator.openCommand
        precondition(command.slug == "open-file-in-editor" && !command.isEnabled())
        command.run()
        precondition(panels == 0)
        coordinator.start()
        precondition(command.isEnabled())
        coordinator.openFile()
        precondition(panels == 1 && coordinator.documents.isEmpty)
        selection = url
        coordinator.openFile()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while coordinator.documents.isEmpty && ContinuousClock.now < deadline { await Task.yield() }
        precondition(coordinator.documents.first?.source == "hello")
        let previous = refreshes
        preferences.set(.markdownFiles, false)
        preferences.set(.plainTextFiles, false)
        while refreshes == previous && ContinuousClock.now < deadline { await Task.yield() }
        precondition(refreshes > previous && !coordinator.isEnabled)
        let previousPanels = panels
        coordinator.openFile()
        precondition(panels == previousPanels && failures == 0)
        coordinator.stop()
        print("Editor open: injected picker, cancellation, loading, gating and refresh passed")
    }
}
