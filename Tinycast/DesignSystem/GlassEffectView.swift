import SwiftUI

struct GlassEffectView: NSViewRepresentable {
    @AppStorage(AppearanceSurfaceStyle.defaultsKey, store: AppearanceStore.preferences)
    private var style = AppearanceSurfaceStyle.glass
    private var effectiveStyle: AppearanceSurfaceStyle { NotchcastPreferences.shared.isOn(.appearance) ? style : .glass }

    func makeNSView(context: Context) -> ThemedSurface {
        ThemedSurface(style: effectiveStyle)
    }

    func updateNSView(_ nsView: ThemedSurface, context: Context) { nsView.apply(effectiveStyle) }
}
