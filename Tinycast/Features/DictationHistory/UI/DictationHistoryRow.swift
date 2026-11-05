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
                Text(verbatim: Self.dateFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Copy") {
                if !Paster.copyPlainText(entry.cleaned) {
                    core.showMessage(String(localized: "Could not copy to clipboard.", table: "Notchcast"), tone: .danger)
                }
            }
            .accessibilityLabel(Text("Copy") + Text(verbatim: " " + Self.dateFormatter.string(from: entry.date)))
        }
        .accessibilityElement(children: .contain)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
