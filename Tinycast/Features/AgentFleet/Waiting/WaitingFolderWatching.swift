import Foundation

@MainActor
protocol WaitingFolderWatching: AnyObject {
    func start(folder: URL, changed: @escaping @MainActor @Sendable () -> Void) throws
    func stop()
}
