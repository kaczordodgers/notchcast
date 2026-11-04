import SwiftUI

struct TorrentSettingsJobRow: View {
    let job: TorrentJob
    let module: TorrentModule

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(verbatim: job.displayName)
            ProgressView(value: job.progress)
                .accessibilityLabel(Text(verbatim: job.displayName))
            HStack {
                Text(job.state.title)
                Text(job.progress, format: .percent.precision(.fractionLength(0)))
                if job.usesIPhone { Text("Wi-Fi + iPhone") }
            }
            .foregroundStyle(.secondary)
            if let error = job.error { Text(error.message).foregroundStyle(.secondary) }
            HStack {
                if job.state.isRunning {
                    Button("Cancel") { module.manager.cancel(job.id) }
                }
                if job.state == .failed || job.state == .cancelled {
                    // ai-design-check-ignore-next-line sentence-case -- upstream's retry label
                    Button("Try Again") { module.tryAgain(job.id) }
                        .disabled(!module.preferences.isOn(.torrents) || !module.isRunning)
                }
                if !job.state.isRunning {
                    Button("Dismiss") { module.manager.dismiss(job.id) }
                }
                // ai-design-check-ignore-next-line sentence-case -- Finder is the macOS app's name
                Button("Show in Finder") { module.manager.reveal(job.id) }
            }
        }
    }
}
