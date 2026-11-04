import Foundation

@MainActor protocol TorrentQueueHost: AnyObject {
    var jobs: [TorrentJob] { get }
    @discardableResult func enqueue(_ urls: [URL], keepSharing: Bool) -> [UUID]
    func cancel(_ id: UUID)
    @discardableResult func tryAgain(_ id: UUID) -> UUID?
    func reveal(_ id: UUID)
    func stop() async
}
