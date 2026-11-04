import Foundation

final class EditorFilePresenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let changed: @Sendable () -> Void

    init(url: URL, changed: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.changed = changed
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedItemDidChange() { changed() }

    func presentedItemDidMove(to newURL: URL) { changed() }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        changed()
        completionHandler(nil)
    }
}
