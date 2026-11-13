// notchcast-sources: Tinycast/Features/Appearance/Model/*.swift
// notchcast-sources: Tinycast/Features/Appearance/Service/*.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Settings/AppAppearance.swift
import AppKit
import SwiftUI

@main
@MainActor
struct AppearanceThemeHooksTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func components(_ color: Color, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    static func dark(_ label: String, _ token: Color, is expected: Color) {
        let actual = components(token, .darkAqua)
        let wanted = components(expected, .darkAqua)
        check("dark \(label)", actual == wanted, "\(actual) != \(wanted)")
    }

    static func main() {
        let c = Theme.Colors.self

        print("# theme hooks preserve token alphas and resolve existing colors live")
        let colors = AppearanceThemeColors.shared
        let text = c.textSecondary
        let selection = c.selection
        let theme = RaycastTheme(
            name: "Hook fixture", author: "", appearance: .dark,
            colors: ["#112233", "#223344", "#335577", "#AACCEE"] + Array(repeating: "#123456", count: 8))
        colors.update(light: nil, dark: theme, preview: nil, opacity: 0.7)
        check("existing text token uses the theme ink", components(text, .darkAqua) == [51, 85, 119, 153])
        check("selection uses its own theme role", components(selection, .darkAqua) == [170, 204, 238, 26])
        check("empty opposite slot keeps upstream ink", components(text, .aqua) == [0, 0, 0, 153])
        colors.update(light: nil, dark: theme, preview: .tinycast(.dark), opacity: 0.7)
        dark("default preview restores upstream selection", selection, is: Color.white.opacity(0.10))
        colors.update(light: nil, dark: nil, preview: nil, opacity: 0.7)
        dark("disabling restores existing text token", text, is: Color.white.opacity(0.60))
        dark("disabling restores existing selection token", selection, is: Color.white.opacity(0.10))

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
