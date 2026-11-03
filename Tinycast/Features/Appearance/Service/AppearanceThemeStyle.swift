import AppKit
import SwiftUI

extension AppearanceThemeColors {
    func ramp(dark: Double, light: Double, role: AppearanceThemeColors.Role = .text) -> Color {
        _ = revision
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return self.ink(role, in: appearance, dark: dark, light: light)
                ?? NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0,
                           blue: isDark ? 1 : 0, alpha: isDark ? dark : light)
        })
    }
}

extension AppearanceStore {
    var backdrop: LinearGradient {
        _ = revision
        return LinearGradient(
            stops: [
                .init(color: background(.background), location: 0),
                .init(color: background(.backgroundSecondary), location: 0.7)
            ], startPoint: .top, endPoint: .bottom)
    }

    @available(macOS 26.0, *)
    func tinted(_ glass: Glass) -> Glass {
        _ = revision
        guard light != nil || dark != nil || previewTarget?.theme != nil else { return glass }
        return glass.tint(background(.background))
    }

    private func background(_ role: AppearanceThemeColors.Role) -> Color {
        Color(nsColor: colors.dynamicColor(role, dark: 1, light: 1, fallback: .clear))
    }
}
