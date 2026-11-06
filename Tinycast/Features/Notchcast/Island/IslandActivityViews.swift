import SwiftUI

/// Home's row and the open header reuse the closed pieces, so an activity reads the same open or closed.
struct IslandActivityGlyph: View {
    let activity: IslandActivity

    var body: some View {
        IslandGlyph(symbol: activity.shownSymbol, tone: activity.tone)
    }
}

struct IslandActivityValue: View {
    let activity: IslandActivity

    var body: some View {
        IslandValueText(value: activity.shownValue)
    }
}

/// A message in the open island's header: its glyph and its text, cancellable while work runs.
struct IslandStatusView: View {
    let message: IslandMessage
    @State private var hovered = false

    var body: some View {
        Group {
            if let cancel = message.onCancel {
                Button(action: cancel) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel \(message.text)")
            } else {
                content
            }
        }
        .onHover { hovered = $0 }
    }

    private var content: some View {
        HStack(spacing: NotchcastTheme.Closed.itemGap) {
            if hovered, message.onCancel != nil {
                IslandGlyph(symbol: "xmark")
            } else {
                IslandGlyph(symbol: message.shownSymbol, tone: IslandItemParts.tone(message.tone),
                            spinning: message.isProgress)
            }
            Text(message.text)
                .font(NotchcastTheme.Typography.title)
                .foregroundStyle(NotchcastTheme.Colors.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, NotchcastTheme.Closed.wingInset)
        .frame(maxWidth: NotchcastTheme.Closed.maximumWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}
