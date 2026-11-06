#if DEBUG
import SwiftUI

struct IslandVisualizerComparisonView: View {
    var isPlaying = true

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(IslandVisualizer.Style.allCases, id: \.self) { style in
                    pill(style, compact: false)
                }
            }
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(IslandVisualizer.Style.allCases, id: \.self) { style in
                    pill(style, compact: true)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .environment(\.colorScheme, .dark)
    }

    private func pill(_ style: IslandVisualizer.Style, compact: Bool) -> some View {
        HStack(spacing: NotchcastTheme.Closed.itemGap) {
            if !compact {
                IslandArtwork(image: nil)
                IslandLines(title: "Teardrop", detail: "Massive Attack")
            } else {
                Text(verbatim: "Teardrop").font(Theme.Typography.rowTrailing)
            }
            IslandVisualizer(isPlaying: isPlaying, style: style)
        }
        .padding(.horizontal, NotchcastTheme.Closed.textInset)
        .frame(height: NotchcastTheme.Closed.row)
        .background(NotchcastTheme.Colors.surface, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
#endif
