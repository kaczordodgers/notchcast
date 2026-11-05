import SwiftUI

struct DictationHistoryRow: View {
    let entry: DictationHistoryEntry
    @Environment(AppCore.self) private var core

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(verbatim: entry.cleaned)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Copy") {
                if !Paster.copyPlainText(entry.cleaned) {
                    core.showMessage(String(localized: "Could not copy to clipboard."), tone: .danger)
                }
            }
            .accessibilityLabel("Copy")
        }
        .accessibilityElement(children: .contain)
    }
}
