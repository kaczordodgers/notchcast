import AppKit

@available(macOS 26.0, *)
@MainActor
final class ThemedSurface: NSView {
    private(set) var style: AppearanceSurfaceStyle
    private var surface: NSView
    private let scheme = SurfaceSchemeKeeper()

    init(style: AppearanceSurfaceStyle) {
        self.style = style
        surface = Self.makeSurface(style)
        super.init(frame: .zero)
        installSurface()
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ style: AppearanceSurfaceStyle) {
        guard self.style != style else { return }
        scheme.update(window: window, pinsDark: style != .glass)
        surface.removeFromSuperview()
        self.style = style
        surface = Self.makeSurface(style)
        installSurface()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheme.update(window: window, pinsDark: style != .glass)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func installSurface() {
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        updateFill()
    }

    private func updateFill() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let spec = style.fill(dark: dark) else { return }
        let fill = NSColor(white: spec.white, alpha: spec.alpha)
        let fillView = style == .matte ? surface.subviews.first : surface
        fillView?.layer?.backgroundColor = fill.cgColor
    }

    private static func makeSurface(_ style: AppearanceSurfaceStyle) -> NSView {
        switch style {
        case .glass:
            return NSGlassEffectView()
        case .black:
            let view = NSView()
            view.wantsLayer = true
            return view
        case .matte:
            let view = NSVisualEffectView()
            view.material = .contentBackground
            view.blendingMode = .behindWindow
            view.state = .active
            let fill = NSView(frame: view.bounds)
            fill.autoresizingMask = [.width, .height]
            fill.wantsLayer = true
            view.addSubview(fill)
            return view
        }
    }
}
