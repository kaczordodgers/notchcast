import SwiftUI

struct DownloadsSettingsSection: View {
    var body: some View {
        Section {
            LabeledContent("Downloads") {
                Text(verbatim: (NotchcastDownloadDestinations.downloads.path as NSString).abbreviatingWithTildeInPath)
                    .textSelection(.enabled)
            }
            LabeledContent("Distill") {
                Text(verbatim: (NotchcastDownloadDestinations.distill.path as NSString).abbreviatingWithTildeInPath)
                    .textSelection(.enabled)
            }
        } header: {
            SettingsSectionHeader(.notchcastDownloads)
        }
    }
}
