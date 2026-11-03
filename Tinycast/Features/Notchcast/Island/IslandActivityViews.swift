import SwiftUI

struct IslandActivityGlyph: View {
    let activity: IslandActivity

    var body: some View {
        SymbolImage(name: activity.progress != nil ? "progress.indicator"
                    : (activity.kind == .timer ? "timer" : "arrow.up.arrow.down"), size: Theme.Size.menuIcon)
            .foregroundStyle(activity.progress != nil ? Theme.Colors.progress : Theme.Colors.textPrimary)
            .accessibilityHidden(true)
    }
}

struct IslandActivityValue: View {
    let activity: IslandActivity
    var multiple = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let end = activity.endDate {
                Text(end, style: .timer)
            } else if let progress = activity.progress {
                Text(progress, format: .percent.precision(.fractionLength(0)))
            } else {
                Text(activity.title).lineLimit(1)
            }
            if multiple {
                Circle().fill(Theme.Colors.textTertiary)
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
            }
        }
        .font(Theme.Typography.rowTrailing)
        .monospacedDigit()
        .accessibilityLabel(activity.title)
    }
}

struct IslandStatusView: View {
    let message: IslandMessage
    @State private var hovered = false

    private var tint: Color {
        switch message.tone {
        case .neutral: message.isProgress ? Theme.Colors.progress : Theme.Colors.textSecondary
        case .success: Theme.Colors.success
        case .danger: Theme.Colors.destructive
        }
    }

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
        HStack(spacing: Theme.Spacing.md) {
            Group {
                if hovered, message.onCancel != nil {
                    SymbolImage(name: "xmark", size: Theme.Size.menuIcon)
                } else if message.isProgress {
                    SymbolImage(name: "progress.indicator", size: Theme.Size.menuIcon)
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                } else {
                    SymbolImage(name: message.tone == .success ? "checkmark"
                                : (message.tone == .danger ? "exclamationmark" : "info"),
                                size: Theme.Size.menuIcon)
                }
            }
            .foregroundStyle(tint)
            Text(message.text).font(Theme.Typography.bar).foregroundStyle(Color.primary).lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(maxWidth: Theme.Size.hudMaxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}
