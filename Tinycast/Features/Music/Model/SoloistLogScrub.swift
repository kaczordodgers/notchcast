import Foundation

struct SoloistLogScrub: Sendable {
    private let key: String?

    init(arguments: [String]) {
        key = arguments.firstIndex(of: "--api-key").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
    }

    func scrub(_ text: String) -> String {
        guard let key, !key.isEmpty else { return text }
        return text.replacingOccurrences(of: key, with: "<key>")
    }
}
