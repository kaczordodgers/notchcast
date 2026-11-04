import Foundation

extension TorrentJob {
    var displayName: String {
        if let name { return name }
        if source.scheme?.lowercased() == "magnet" {
            let displayName = URLComponents(url: source, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "dn" })?.value
            return displayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Magnet link")
        }
        return source.lastPathComponent
    }

    var progress: Double {
        guard bytesTotal > 0 else { return 0 }
        return min(1, max(0, Double(bytesDone) / Double(bytesTotal)))
    }
}

extension TorrentJob.State {
    var title: String {
        switch self {
        case .findingPeers: String(localized: "Finding peers")
        case .downloading: String(localized: "Downloading")
        case .sharing: String(localized: "Sharing")
        case .finished: String(localized: "Finished")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}

extension TorrentFailure {
    var message: String {
        switch self {
        case .toolNotInstalled: String(localized: "aria2c not found")
        case .invalidInput, .unreadableTorrent, .invalidTorrent:
            String(localized: "This torrent file or magnet link could not be read.")
        case .alreadyRunning: String(localized: "This torrent is already running.")
        case .launchFailed: String(localized: "aria2c could not start.")
        case .listenerNotOwned: String(localized: "The aria2c connection could not be verified.")
        case .rpcUnavailable, .invalidResponse: String(localized: "The aria2c connection failed.")
        case .rpc, .download: String(localized: "The download failed.")
        case .noPeers: String(localized: "No peers found in 10 minutes.")
        }
    }
}
