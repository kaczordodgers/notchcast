@MainActor
enum NotchcastLauncher {
    static func open() {
        AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
    }
}
