import Foundation

nonisolated struct DistillConversion: Sendable {
    var markdown: String
    var retainSource = true

    enum Failure: Error {
        case unreadable, empty, tooLarge, sourceChanged, outputChanged, unsafePath, noOutputName
    }

    struct Result: Sendable {
        let source: URL
        let output: URL?
        let status: Status
    }

    enum Status: Sendable, Equatable {
        case converted, retained
        case skipped(SkipReason)
        case failed(String)
    }

    enum SkipReason: Sendable, Equatable {
        case markdown, generated, symbolicLink, unsupported, htmlUnavailable, mediaUnavailable
    }

    static func literal(_ text: String, source: URL, retainSource: Bool = false) -> Self {
        let longest = text.split(omittingEmptySubsequences: false) { $0 != "`" }.map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longest + 1))
        let name = source.lastPathComponent.replacingOccurrences(of: "\n", with: " ")
        let body = "# \(name)\n\n\(fence)\n\(text)\(text.hasSuffix("\n") ? "" : "\n")\(fence)\n"
        return Self(markdown: body, retainSource: retainSource)
    }
}
