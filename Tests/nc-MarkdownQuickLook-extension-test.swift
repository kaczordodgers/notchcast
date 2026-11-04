// notchcast-sources: NotchcastMarkdownPreview/MarkdownPreviewController.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Model/MarkdownQuickLookDocument.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/MarkdownQuickLookReader.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdown.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteMarkdownParser.swift
// notchcast-sources: Tinycast/Features/Notes/Model/NoteInlineScanner.swift
// notchcast-sources: Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift
// notchcast-sources: Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift
// notchcast-sources: Tinycast/Features/Notes/UI/NoteBlockDecoration.swift
// notchcast-sources: Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift
// notchcast-sources: Tinycast/Features/Notes/UI/NoteLayoutFragmentProvider.swift
// notchcast-sources: Tinycast/Features/Notes/UI/NoteCheckboxGeometry.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift
import AppKit

@main
struct MarkdownPreviewTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("preview.md")
        let source = "# Title\n\n**Bold**\n- [x] Task\n```mermaid\ngraph TD; A-->B\n```\n"
        try Data(source.utf8).write(to: file)
        let controller = MarkdownPreviewController()
        try await controller.preparePreviewOfFile(at: file)
        guard let scroll = controller.view as? NSScrollView,
            let text = scroll.documentView as? NSTextView, let storage = text.textStorage
        else { preconditionFailure("Missing native text preview") }
        precondition(text.string == source && !text.isEditable && !text.importsGraphics)
        precondition(text.textLayoutManager?.delegate is NoteLayoutFragmentProvider)
        precondition(text.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        precondition(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont == NoteMarkdownTypography.heading1)
        precondition(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NoteMarkdownTypography.hidden)
        let task = (source as NSString).range(of: "- [x]").location
        precondition(storage.attribute(.noteBlockDecoration, at: task, effectiveRange: nil) is NoteBlockDecoration)
        let graph = (source as NSString).range(of: "graph").location
        precondition(storage.attribute(.font, at: graph, effectiveRange: nil) as? NSFont == NoteMarkdownTypography.codeBlock)
        let data = try Data(contentsOf: file)
        precondition(data == Data(source.utf8))
        print("Extension: native read-only TextKit, forced dark, Notes headings, markers, tasks and code pass")
        print("Extension: Mermaid stays literal; no WebKit, network requests or source writes")

        try Data("Second".utf8).write(to: file)
        try await controller.preparePreviewOfFile(at: file)
        precondition(text.string == "Second")
        try Data([0xFF]).write(to: file)
        do {
            try await controller.preparePreviewOfFile(at: file)
            preconditionFailure("Invalid document did not fail")
        } catch is CocoaError {}
        print("Extension: replacement and preparation failure pass without opening a panel")
    }
}
