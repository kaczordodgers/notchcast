import SwiftUI

struct IslandClosedContent: View {
    let parts: IslandItemParts

    var body: some View {
        HStack(spacing: NotchcastTheme.Closed.itemGap) {
            parts.leading
            if case .message(let message) = parts.item {
                VStack(alignment: .leading, spacing: NotchcastTheme.Closed.lineSpacing) {
                    Text(message.text)
                        .font(NotchcastTheme.Typography.title)
                    if let detail = message.detail {
                        Text(detail)
                            .font(NotchcastTheme.Typography.detail)
                            .foregroundStyle(NotchcastTheme.Colors.secondary)
                    }
                }
                .fixedSize()
            } else {
                parts.lines
            }
            if parts.hasTrailing { parts.trailing(compact: false) }
        }
        .padding(.horizontal, NotchcastTheme.Closed.contentInset)
        .frame(height: NotchcastTheme.Closed.row)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}
