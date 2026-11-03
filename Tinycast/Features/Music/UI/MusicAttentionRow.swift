import SwiftUI

struct MusicAttentionRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    var isFailure = false
    var buttonTitle: LocalizedStringResource = "Open Settings"
    var action: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: symbol, size: Theme.Radius.dialogSymbol, monochrome: true)
                .foregroundStyle(isFailure ? Theme.Colors.destructive : Theme.Colors.warning)
                .frame(width: Theme.Size.resultRowIcon, height: Theme.Size.resultRowIcon)
                .accessibilityHidden(true)
            HStack(spacing: Theme.Spacing.sm) {
                Text(title).foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle).foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(Theme.Typography.rowTitle).lineLimit(1).truncationMode(.tail)
            .accessibilityElement(children: .combine)
            Spacer()
            Button(action: action) { Text(buttonTitle) }
                .buttonStyle(.modalAction(.standard, fillsWidth: false))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}
