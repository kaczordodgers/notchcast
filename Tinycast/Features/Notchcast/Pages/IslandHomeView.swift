import SwiftUI

struct IslandHomeView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: "house", size: Theme.Size.dialogIcon)
                .accessibilityHidden(true)
            Text("Nothing running right now")
                .font(Theme.Typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}
