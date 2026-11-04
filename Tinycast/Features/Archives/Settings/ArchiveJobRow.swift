import SwiftUI

struct ArchiveJobRow: View {
    let job: ArchiveJob
    let module: ArchiveModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            LabeledContent {
                Text(job.stateTitle)
                    .foregroundStyle(.secondary)
            } label: {
                Text(verbatim: job.archive.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if job.totalBytes > 0 {
                ProgressView(value: Double(job.bytesWritten), total: Double(job.totalBytes))
                    .accessibilityLabel(Text("Extraction progress"))
            }
            if let failure = job.failure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = job.fallbackNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if job.canCancel {
                    Button("Cancel") { module.queue.cancel(job.id) }
                }
                if job.canRetry {
                    Button(String(localized: "Try Again")) { module.retry(job.id) }
                        .settingsEnabled(preferences.isOn(.archives) && module.isRunning)
                }
                Button(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([job.output ?? job.archive])
                }
            }
        }
    }
}
