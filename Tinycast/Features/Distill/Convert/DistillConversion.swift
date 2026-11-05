import Foundation

nonisolated struct DistillConversion: Sendable {
    var markdown: String
    var retainSource = true

    enum Failure: LocalizedError {
        case unreadable, empty, tooLarge, sourceChanged, outputChanged, unsafePath, noOutputName

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "The source could not be read.", table: "Notchcast")
            case .empty: String(localized: "The source contains no readable text.", table: "Notchcast")
            case .tooLarge: String(localized: "The file exceeds the conversion size limit.", table: "Notchcast")
            case .sourceChanged: String(localized: "The source changed during conversion. Try again.", table: "Notchcast")
            case .outputChanged: String(localized: "The converted output changed. The original was kept.", table: "Notchcast")
            case .unsafePath: String(localized: "The file path is unsafe for conversion.", table: "Notchcast")
            case .noOutputName: String(localized: "No unused name is available for the converted output.", table: "Notchcast")
            }
        }
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
