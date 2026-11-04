import Foundation

protocol TorrentToolLocating: Sendable {
    func aria2c() -> URL?
}
