import Foundation

struct TorrentToolLocator: TorrentToolLocating {
    func aria2c() -> URL? { ExecutableLocator.find("aria2c") }
}
