import AppKit
import SwiftUI

// The extension has no app themes, so Theme's tokens resolve to their plain ink.
final class AppearanceThemeColors: Sendable {
    enum Role: Sendable {
        case text, selection, background, backgroundSecondary
    }

    static let shared = AppearanceThemeColors()

    func ramp(dark: Double, light: Double, role _: Role = .text) -> Color {
        Theme.Colors.adaptive(dark: .srgbInk(1, alpha: dark), light: .srgbInk(0, alpha: light))
    }

    static func tinted(_ glass: Glass) -> Glass { glass }
}
