import Foundation

enum ShelfEngine {
    static let maximumItemBytes = 24 * 1024
    static let maximumItems = 64

    enum Failure: Error { case oversized, invalidItem, peerDown, stopped, full }

    static func validate(_ item: ShelfItem) throws {
        guard item.data.count <= maximumItemBytes else { throw Failure.oversized }
        guard !item.data.isEmpty, !item.name.isEmpty, item.name.utf8.count <= 255,
              !item.name.contains("/"), !item.name.contains("\\"),
              !item.name.contains("\u{0}"), item.name != ".", item.name != ".." else {
            throw Failure.invalidItem
        }
        if item.kind != .file {
            guard let text = String(data: item.data, encoding: .utf8) else { throw Failure.invalidItem }
            if item.kind == .link {
                guard let url = URL(string: text), ["https", "http"].contains(url.scheme),
                      url.host != nil else { throw Failure.invalidItem }
            }
        }
    }
}
