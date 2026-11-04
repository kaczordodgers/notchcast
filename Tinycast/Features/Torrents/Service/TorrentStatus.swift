import Foundation

struct TorrentStatus: Decodable, Sendable {
    struct File: Decodable, Sendable { let path: String }
    struct BitTorrent: Decodable, Sendable {
        struct Info: Decodable, Sendable { let name: String? }
        let info: Info?
    }

    let status: String
    var totalLength: String?
    var completedLength: String?
    var downloadSpeed: String?
    var connections: String?
    var numSeeders: String?
    var seeder: String?
    var errorCode: String?
    var errorMessage: String?
    var infoHash: String?
    var followedBy: [String]?
    var files: [File]?
    var bittorrent: BitTorrent?

    var bytesDone: Int64 { max(0, Int64(completedLength ?? "") ?? 0) }
    var bytesTotal: Int64 { max(0, Int64(totalLength ?? "") ?? 0) }
    var speed: Int64 { max(0, Int64(downloadSpeed ?? "") ?? 0) }
    var peers: Int { max(0, Int(connections ?? "") ?? 0) }
    var seeders: Int { max(0, Int(numSeeders ?? "") ?? 0) }
}
