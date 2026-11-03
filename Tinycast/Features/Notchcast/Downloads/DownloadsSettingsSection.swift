import SwiftUI

struct DownloadsSettingsSection: View {
    var body: some View {
        Section {
            LabeledContent("Downloads") {
                Text(verbatim: "~/Downloads")
                    .textSelection(.enabled)
            }
            LabeledContent("Distill") {
                Text(verbatim: "~/Downloads/Distill/Raw")
                    .textSelection(.enabled)
            }
        } header: {
            Text("Downloads")
        }
    }
}
