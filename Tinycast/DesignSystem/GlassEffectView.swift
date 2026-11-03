import SwiftUI

struct GlassEffectView: NSViewRepresentable {
    @AppStorage(AppearanceSurfaceStyle.defaultsKey) private var style = AppearanceSurfaceStyle.glass

    func makeNSView(context: Context) -> ThemedSurface {
        ThemedSurface(style: style)
    }

    func updateNSView(_ nsView: ThemedSurface, context: Context) { nsView.apply(style) }
}
