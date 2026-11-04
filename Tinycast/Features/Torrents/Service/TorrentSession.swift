import Foundation

@MainActor protocol TorrentSession: AnyObject {
    var isAlive: Bool { get }
    func start(extraArguments: [String]) async throws
    func add(_ submission: TorrentSubmission, destination: URL, keepSharing: Bool) async throws -> String
    func status(_ gid: String) async throws -> TorrentStatus
    func remove(_ gid: String) async throws
    func stop() async
    func terminate()
}
