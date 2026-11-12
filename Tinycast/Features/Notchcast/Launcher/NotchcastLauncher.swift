@MainActor
enum NotchcastLauncher {
    static func open() {
        NotchcastHost.current.showLauncher()
    }
}
