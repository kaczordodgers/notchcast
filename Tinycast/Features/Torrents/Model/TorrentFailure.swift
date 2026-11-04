import Foundation

enum TorrentFailure: Error, Equatable, Sendable {
    case toolNotInstalled
    case invalidInput
    case unreadableTorrent
    case invalidTorrent
    case alreadyRunning
    case launchFailed
    case listenerNotOwned
    case rpcUnavailable
    case invalidResponse
    case rpc(code: Int, message: String)
    case download(code: String, message: String)
    case noPeers
}
