import SwiftUI

struct DownloadsFolderSettingRow: View {
    var body: some View {
        LabeledContent(String(localized: "Downloads", table: "Notchcast")) {
            Text(verbatim: (NotchcastDownloadDestinations.downloads.path as NSString).abbreviatingWithTildeInPath)
                .textSelection(.enabled)
        }
    }
}

struct DistillFolderSettingRow: View {
    var body: some View {
        LabeledContent(String(localized: "Distill", table: "Notchcast")) {
            Text(verbatim: (NotchcastDownloadDestinations.distill.path as NSString).abbreviatingWithTildeInPath)
                .textSelection(.enabled)
        }
    }
}

struct TorrentToolSettingRow: View {
    let module: TorrentModule

    var body: some View {
        LabeledContent {
            if let url = module.toolURL {
                Text(verbatim: url.path).textSelection(.enabled)
            } else if !module.toolChecked {
                Text("Checking…")
            } else {
                Text("aria2c not found", tableName: "Notchcast")
            }
        } label: {
            SettingsRowTitle(.notchcastTorrents, LocalizedStringResource("aria2c", table: "Notchcast"))
            Text("Install aria2c with Homebrew: brew install aria2", tableName: "Notchcast")
        }
        .task { await module.refreshTool() }
    }
}

struct TorrentJobsSettingRow: View {
    let module: TorrentModule

    var body: some View {
        ForEach(module.manager.jobs) { job in
            TorrentSettingsJobRow(job: job, module: module)
        }
    }
}
