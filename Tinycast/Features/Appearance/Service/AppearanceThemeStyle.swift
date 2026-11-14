import AppKit
import SwiftUI

extension AppearanceThemeColors {
    func ramp(dark: Double, light: Double, role: AppearanceThemeColors.Role = .text) -> Color {
        _ = revision
        return Color(nsColor: NSColor(name: nil) { appearance in
            _ = self.revision
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return self.ink(role, in: appearance, dark: dark, light: light)
                ?? NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0,
                           blue: isDark ? 1 : 0, alpha: isDark ? dark : light)
        })
    }
}

extension AppearanceThemeColors {
    @MainActor static func backdrop(hidden: Bool) -> AnyShapeStyle {
        if hidden { return AnyShapeStyle(Color.clear) }
        let surface = surfaceFill
        return surface.map { AnyShapeStyle($0) } ?? AnyShapeStyle(shared.backdrop)
    }

    @MainActor static var surfaceFill: Color? {
        guard let style = AppearanceStore.current?.effectiveSurfaceStyle, style != .glass else { return nil }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let spec = style.fill(dark: dark) ?? (0, 0)
            return NSColor(white: spec.0, alpha: spec.1)
        })
    }

    static func tinted(_ glass: Glass) -> Glass {
        guard shared.hasPalette else { return glass }
        return glass.tint(shared.background(.background))
    }

    private var backdrop: LinearGradient {
        _ = revision
        return LinearGradient(
            stops: [
                .init(color: background(.background), location: 0),
                .init(color: background(.backgroundSecondary), location: 0.7)
            ], startPoint: .top, endPoint: .bottom)
    }

    private func background(_ role: AppearanceThemeColors.Role) -> Color {
        Color(nsColor: dynamicColor(role, dark: 1, light: 1, fallback: .clear))
    }
}
