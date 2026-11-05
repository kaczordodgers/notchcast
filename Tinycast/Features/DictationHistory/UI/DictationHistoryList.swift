import SwiftUI

struct DictationHistoryList: View {
    let entries: [DictationHistoryEntry]

    var body: some View {
        if entries.isEmpty {
            Text("Nothing here yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(entries) { entry in
                DictationHistoryRow(entry: entry)
            }
        }
    }
}
