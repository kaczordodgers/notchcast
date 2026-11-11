import Foundation

extension TorrentModule: NotchcastRegistrant {
    static let shared = TorrentModule(
        session: TorrentAria2Session(stateDirectory: NotchcastIdentity.supportRoot.appending(path: "Torrents")))

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.torrents], module: shared)]
    }
}
