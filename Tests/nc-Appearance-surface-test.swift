import AppKit
import Foundation

@main
struct AppearanceSurfaceTest {
    @MainActor
    static func main() {
        guard #available(macOS 26.0, *) else { fatalError("macOS 26 required") }
        let surface = ThemedSurface(style: .glass)
        precondition(surface.subviews.count == 1 && surface.subviews[0] is NSGlassEffectView)
        let glass = surface.subviews[0]
        surface.apply(.glass)
        precondition(surface.subviews[0] === glass)
        surface.setFrameSize(NSSize(width: 400, height: 200))
        surface.apply(.black)
        precondition(surface.subviews.count == 1 && !(surface.subviews[0] is NSGlassEffectView))
        precondition(surface.subviews[0].frame == surface.bounds)
        precondition(surface.subviews[0].layer?.backgroundColor == NSColor.black.cgColor)
        surface.apply(.matte)
        guard let matte = surface.subviews.first as? NSVisualEffectView else { fatalError("native matte material") }
        precondition(matte.material == .contentBackground && matte.blendingMode == .behindWindow)
        guard let fill = matte.subviews.first else { fatalError("matte fill over the native blur") }
        precondition(fill.frame == surface.bounds)
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.viewDidChangeEffectiveAppearance()
        precondition(fill.layer?.backgroundColor == NSColor.black.withAlphaComponent(0.42).cgColor)
        surface.appearance = NSAppearance(named: .aqua)
        surface.viewDidChangeEffectiveAppearance()
        precondition(fill.layer?.backgroundColor == NSColor.white.withAlphaComponent(0.68).cgColor)
        surface.apply(.glass)
        precondition(surface.subviews.count == 1 && surface.subviews[0] is NSGlassEffectView)
        let point = NSPoint(x: 100, y: 100)
        precondition(surface.hitTest(point) === surface.subviews[0].hitTest(point))
        print("Surface checks passed: native glass, opaque black, adaptive matte, native hit testing")
    }
}
