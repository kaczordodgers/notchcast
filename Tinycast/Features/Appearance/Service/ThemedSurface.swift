import AppKit

@available(macOS 26.0, *)
@MainActor
final class ThemedSurface: NSView {
    private(set) var style: AppearanceSurfaceStyle
    private var surface: NSView

    init(style: AppearanceSurfaceStyle) {
        self.style = style
        surface = Self.makeSurface(style)
        super.init(frame: .zero)
        installSurface()
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ style: AppearanceSurfaceStyle) {
        guard self.style != style else { return }
        surface.removeFromSuperview()
        self.style = style
        surface = Self.makeSurface(style)
        installSurface()
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
        guard style != .glass else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor = style == .black ? .black : (dark ? .black.withAlphaComponent(0.42)
            : .white.withAlphaComponent(0.68))
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
