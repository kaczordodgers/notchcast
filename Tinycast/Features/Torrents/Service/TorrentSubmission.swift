import CryptoKit
import Foundation

struct TorrentSubmission: Sendable {
    enum Payload: Sendable {
        case torrent(Data)
        case magnet(URL)
    }

    let payload: Payload
    let infoHash: String
    let name: String?

    @concurrent static func read(_ url: URL) async throws -> Self {
        try Task.checkCancellation()
        if url.scheme?.lowercased() == "magnet" {
            return Self(payload: .magnet(url), infoHash: try TorrentMetainfo.magnetHash(url), name: nil)
        }
        guard url.isFileURL, url.pathExtension.lowercased() == "torrent" else { throw TorrentFailure.invalidInput }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
        } catch {
            throw TorrentFailure.unreadableTorrent
        }
        guard data.count <= 16 * 1024 * 1024 else { throw TorrentFailure.invalidTorrent }
        let metainfo = try TorrentMetainfo.read(data)
        let hash = Insecure.SHA1.hash(data: metainfo.info).map { String(format: "%02x", $0) }.joined()
        try Task.checkCancellation()
        return Self(payload: .torrent(data), infoHash: hash, name: metainfo.name)
    }
}
