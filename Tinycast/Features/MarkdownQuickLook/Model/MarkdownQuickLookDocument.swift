import Foundation

struct MarkdownQuickLookDocument: Sendable {
    static let maximumBytes = 1_048_576

    let source: String
    let markdown: NoteMarkdown

    init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        guard var source = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if source.first == "\u{FEFF}" { source.removeFirst() }
        self.source = source
        markdown = NoteMarkdownParser.parse(units: Array(source.utf16))
    }
}
