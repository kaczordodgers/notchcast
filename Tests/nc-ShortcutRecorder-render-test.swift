// notchcast-hosted-only

// notchcast-sources: Tinycast/Features/HotKeys/UI/ShortcutRecorder.swift Tinycast/Features/HotKeys/Model/HotKeyBinding.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HyperKey.swift Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Service/KeyShortcut.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/HotKeyManager.swift Tinycast/Platform/ASCIIKeyboardLayout.swift
// notchcast-sources: Tests/HotKeyDispatchFixtures.swift Tinycast/DesignSystem/KeyCapChip.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: notchcast/vendor/Obsidian/ObsidianTokens.swift Tinycast/Features/Notchcast/IslandButtonFill.swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@main
struct ShortcutRecorderRenderTest {
    static func main() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        check(key: kVK_ANSI_K, flags: [.control, .option, .shift, .command], capCount: 5)
        check(key: kVK_Space, flags: [.control, .option, .command], capCount: 4)
        check(key: kVK_Space, flags: [.control, .option, .shift, .command], capCount: 5)
        check(key: kVK_Space, flags: [.function, .control, .option, .shift, .command], capCount: 6)
        print("PASS shortcut recorder keeps every cap in place and reveals clear beside them")
    }

    static func check(key: Int, flags: NSEvent.ModifierFlags, capCount: Int) {
        let binding = HotKeyBinding.combo(KeyShortcut(keyCode: key, modifierFlags: flags)!)
        precondition(binding.recorderKeycaps.count == capCount)
        let resting = render(binding, hovered: false)
        let hovered = render(binding, hovered: true)
        precondition(resting.width == hovered.width && resting.height == hovered.height,
                     "The recorder changed size on hover")

        let restingBands = inkBands(in: resting)
        let hoveredBands = inkBands(in: hovered)
        precondition(restingBands.count == capCount, "A keycap is missing at rest: \(restingBands)")
        precondition(Array(hoveredBands.dropLast()) == restingBands, "Hover moved or obscured a keycap")
    }

    static func render(_ binding: HotKeyBinding, hovered: Bool) -> CGImage {
        let content = ShortcutRecorderBindingLabel(binding: binding, showsAccessibilityWarning: false,
                                                   hovered: hovered, onClear: {})
            .padding(.horizontal, ShortcutRecorder.horizontalInset)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: Theme.Size.shortcutRecorder,
                                                 height: Theme.Size.settingsRowButton)
        renderer.scale = 2
        guard let image = renderer.cgImage else { fatalError("Recorder did not render") }
        precondition(image.width <= Int(Theme.Size.shortcutRecorder * renderer.scale),
                     "The binding needs more space than the recorder provides")
        return image
    }

    static func inkBands(in image: CGImage) -> [Range<Int>] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var bands: [Range<Int>] = []
        var start: Int?
        for x in 0...width {
            if x < width && (0..<height).contains(where: { pixels[($0 * width + x) * 4 + 3] > 4 }) {
                if start == nil { start = x }
            } else if let first = start {
                bands.append(first..<x)
                start = nil
            }
        }
        return bands
    }
}

extension ModifierTapMonitor {
    var needsAccessibility: Bool { false }
}

extension ShortcutCaptureSession {
    func setActiveRecorderView(_ view: NSView) {}
    func clearActiveRecorderView(_ view: NSView) {}
}

enum Permissions {
    static func openAccessibilitySettings() {}
}

struct ShortcutRecorderAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {}
}

extension EnvironmentValues {
    var shortcutDeepLink: ShortcutDeepLink? { nil }
}

struct ShortcutDeepLink {
    func url(_ action: HotKeyAction) -> URL? { nil }
    func copy(_ url: URL) {}
}
