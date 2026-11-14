import AppKit
import SwiftUI

/// Black and Matte are dark surfaces, so the window holding one is pinned to Dark.
@MainActor
final class SurfaceSchemeKeeper {
    private weak var window: NSWindow?
    private var original: NSAppearance?
    private var pinned = false

    func update(window newWindow: NSWindow?, pinsDark: Bool) {
        if newWindow !== window { release() }
        guard let newWindow else { return }
        window = newWindow
        if pinsDark, !pinned {
            original = newWindow.appearance
            newWindow.appearance = NSAppearance(named: .darkAqua)
            pinned = true
        } else if !pinsDark {
            release()
        }
    }

    func release() {
        if pinned { window?.appearance = original }
        pinned = false
        original = nil
        window = nil
    }

    static var pinsDark: Bool {
        guard let style = AppearanceStore.current?.effectiveSurfaceStyle else { return false }
        return style != .glass
    }
}

struct SurfaceBackdrop<S: Shape>: View {
    let fill: AnyShapeStyle
    let shape: S

    var body: some View {
        shape.fill(fill).background(SurfaceSchemeAnchor(pinsDark: SurfaceSchemeKeeper.pinsDark))
    }
}

private struct SurfaceSchemeAnchor: NSViewRepresentable {
    let pinsDark: Bool

    final class Anchor: NSView {
        let keeper = SurfaceSchemeKeeper()
        var pinsDark = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            keeper.update(window: window, pinsDark: pinsDark)
        }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }

    func updateNSView(_ view: Anchor, context: Context) {
        view.pinsDark = pinsDark
        view.keeper.update(window: view.window, pinsDark: pinsDark)
    }
}

extension AppearanceThemeColors {
    @MainActor static var surfaceBackdropStyle: AnyShapeStyle {
        AnyShapeStyle(surfaceFill ?? .clear)
    }
}
