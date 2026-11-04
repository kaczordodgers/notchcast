import Foundation

struct TorrentJob: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case findingPeers, downloading, sharing, finished, failed, cancelled

        var isRunning: Bool {
            self == .findingPeers || self == .downloading || self == .sharing
        }
    }

    let id: UUID
    let source: URL
    let destination: URL
    let keepSharing: Bool
    var name: String?
    var infoHash: String?
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var speed: Int64 = 0
    var peers = 0
    var seeders = 0
    var state: State = .findingPeers
    var error: TorrentFailure?
    var files: [URL] = []
    var usesIPhone = false

    var timeLeft: TimeInterval? {
        guard speed > 0, bytesTotal > bytesDone else { return nil }
        return Double(bytesTotal - bytesDone) / Double(speed)
    }
}
