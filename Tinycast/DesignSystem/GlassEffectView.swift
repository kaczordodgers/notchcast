import SwiftUI

struct GlassEffectView: NSViewRepresentable {
    @AppStorage(AppearanceSurfaceStyle.defaultsKey, store: AppearanceStore.preferences)
    private var style = AppearanceSurfaceStyle.glass

    func makeNSView(context: Context) -> ThemedSurface {
        ThemedSurface(style: style)
    }

    func updateNSView(_ nsView: ThemedSurface, context: Context) { nsView.apply(style) }
}
