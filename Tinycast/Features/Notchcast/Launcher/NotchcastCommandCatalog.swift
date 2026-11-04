import Foundation

enum NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
    ]

    static var entries: [AppEntry] { all.map(\.entry) }

    static func command(for id: String) -> NotchcastCommand? {
        all.first { $0.id == id || $0.legacyID == id }
    }

    @MainActor static func isEnabled(_ id: String) -> Bool {
        command(for: id)?.isEnabled() ?? true
    }

    @MainActor static func dispatch(_ id: String, dismiss: () -> Void) -> Bool {
        guard let command = command(for: id) else { return false }
        if command.isEnabled() {
            dismiss()
            command.run()
        }
        return true
    }

    @MainActor static func perform(_ id: String) {
        _ = dispatch(id) {
            let paletteCoordinator = AppCore.shared.paletteCoordinator
            guard paletteCoordinator.isVisible else { return }
            paletteCoordinator.hidePalette(restoreFocus: false)
        }
    }
}
