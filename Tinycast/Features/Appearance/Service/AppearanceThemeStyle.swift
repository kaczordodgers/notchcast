import AppKit
import SwiftUI

extension AppearanceThemeColors {
    func ramp(dark: Double, light: Double, role: AppearanceThemeColors.Role = .text) -> Color {
        Color(AppearanceRamp(colors: self, dark: dark, light: light, role: role))
    }
}

private struct AppearanceRamp: ShapeStyle, Hashable {
    let colors: AppearanceThemeColors
    let dark: Double
    let light: Double
    let role: AppearanceThemeColors.Role

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        _ = colors.revision
        let isDark = environment.colorScheme == .dark
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        let color = colors.ink(role, in: appearance, dark: dark, light: light)
            ?? NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0,
                       blue: isDark ? 1 : 0, alpha: isDark ? dark : light)
        return Color(nsColor: color).resolve(in: environment)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.colors === rhs.colors && lhs.dark == rhs.dark && lhs.light == rhs.light && lhs.role == rhs.role
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(colors))
        hasher.combine(dark)
        hasher.combine(light)
        hasher.combine(role)
    }
}

extension AppearanceThemeColors {
    @MainActor static func backdrop(hidden: Bool) -> AnyShapeStyle {
        hidden ? AnyShapeStyle(Color.clear) : AnyShapeStyle(shared.backdrop)
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
