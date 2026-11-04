import SwiftUI

struct ThemeSwatch: View {
    let theme: RaycastTheme?
    @Environment(\.metrics) private var metrics

    private var colors: [Color] {
        guard let theme, theme.isValid else {
            return [Theme.Colors.controlSurface, Theme.Colors.rowHover, Theme.Colors.textPrimary,
                    Theme.Colors.selection, Theme.Colors.textSecondary, Theme.Colors.textTertiary]
        }
        return [0, 1, 2, 3, 5, 6].map { index in
            let value = UInt32(theme.colors[index].dropFirst(), radix: 16) ?? 0
            return Color(
                .sRGB, red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        }
    }

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            ForEach(colors.indices, id: \.self) { index in
                ColorDot(color: colors[index])
                    .scaleEffect(AppearanceMetrics.swatchDot / Theme.Size.colorDot)
                    .frame(
                        width: metrics.scaled(AppearanceMetrics.swatchDot),
                        height: metrics.scaled(AppearanceMetrics.swatchDot))
            }
        }
        .accessibilityHidden(true)
    }
}
