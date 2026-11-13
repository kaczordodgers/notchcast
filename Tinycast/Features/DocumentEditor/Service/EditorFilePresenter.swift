import Foundation
import Synchronization

final class EditorFilePresenter: NSObject, NSFilePresenter, Sendable {
    private let location: Mutex<URL>
    var presentedItemURL: URL? { location.withLock { $0 } }
    let presentedItemOperationQueue = OperationQueue()
    private let changed: @Sendable (URL) -> Void

    init(url: URL, changed: @escaping @Sendable (URL) -> Void) {
        location = Mutex(url)
        self.changed = changed
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedItemDidChange() { changed(location.withLock { $0 }) }

    func presentedItemDidMove(to newURL: URL) {
        location.withLock { $0 = newURL }
        changed(newURL)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        changed(location.withLock { $0 })
        completionHandler(nil)
    }
}
