import SwiftUI

struct ForkSettingsBackupCopiesView: View {
    let copies: [ForkSettingsBackupService.Copy]
    let restore: (String) -> Void

    var body: some View {
        if copies.isEmpty {
            Text("No settings backup was found.", tableName: "Notchcast").foregroundStyle(.secondary)
        } else {
            ForEach(copies) { copy in
                LabeledContent {
                    Button(String(localized: "Restore", table: "Notchcast")) { restore(copy.name) }
                        .settingsEnabled(copy.valid)
                } label: {
                    Text(copy.date, format: .dateTime.year().month().day().hour().minute().second())
                    if copy.valid, let size = copy.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    } else {
                        Text("Unreadable or invalid backup.", tableName: "Notchcast")
                    }
                }
            }
        }
    }
}
