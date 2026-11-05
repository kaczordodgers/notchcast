import SwiftUI

struct SpotifyBuildRow: View {
    let module: SpotifyConnectModule
    let install: () -> Void

    var body: some View {
        LabeledContent {
            if module.speaker.state == .downloading {
                ProgressView().controlSize(.small)
            } else if needsDownload {
                // ai-design-check-ignore-next-line sentence-case -- Soloist is a product name.
                Button(String(localized: "Download Soloist", table: "Notchcast"), action: install)
            }
        } label: {
            if module.speaker.state == .downloading {
                // ai-design-check-ignore-next-line sentence-case -- Soloist is a product name.
                Text("Downloading Soloist…", tableName: "Notchcast")
                Text("Spotify’s player, downloaded from Spotify.", tableName: "Notchcast")
            } else if let build = module.speaker.build {
                Text("Soloist \(build.version)", tableName: "Notchcast")
                Text("Expires \(build.expires.formatted(.dateTime.day().month(.abbreviated).year()))", tableName: "Notchcast")
            } else {
                Text("Not installed")
                Text("Spotify’s player, downloaded from Spotify.", tableName: "Notchcast")
            }
        }
        .task { await module.speaker.refreshInstalledBuild() }
    }

    private var needsDownload: Bool {
        if module.speaker.build == nil { return true }
        return switch module.speaker.state {
        case .expiresSoon, .needsBuild: true
        default: false
        }
    }
}
