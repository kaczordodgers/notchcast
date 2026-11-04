import Foundation

extension NotchcastCore {
    static let torrents = TorrentModule(
        session: TorrentAria2Session(stateDirectory: AppPaths.applicationSupport().appending(path: "Torrents")))
}
