// notchcast-sources: Tinycast/Features/Appearance/Model/*.swift
// notchcast-sources: Tinycast/Features/Appearance/Service/*.swift
// notchcast-sources: Tinycast/Features/Appearance/UI/AppearanceCoordinator.swift
// notchcast-sources: Tinycast/Features/Appearance/UI/ThemeImportDialog.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogRequest.swift
// notchcast-kit: core
import AppKit

enum PaletteMode { case launcher, theme }
enum AppURLScheme { static let current = "notchcast-fixture" }
final class VolumeState {}
final class SnippetArgumentsState {}
final class ClipboardEditState {}

@MainActor final class PaletteState {
    var mode = PaletteMode.launcher
}

@MainActor final class PaletteCoordinator {
    var anchorView: NSView?
    var opened: PaletteMode?
    var popped = false
    func togglePalette(mode: PaletteMode) { opened = mode }
    func popToRootNow() { popped = true }
}

@MainActor final class AppCore {
    let palette = PaletteState()
    let paletteCoordinator = PaletteCoordinator()
    var messages: [String] = []
    var dialog: [DialogAction] = []
    var defaultIndex: Int?
    var continuation: CheckedContinuation<Int, Never>?
    var failures = 0

    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction], defaultIndex: Int
    ) async -> Int {
        dialog = options
        self.defaultIndex = defaultIndex
        return await withCheckedContinuation { continuation = $0 }
    }

    func answer(_ choice: Int) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: choice)
    }

    func showMessage(_ message: String, tone: DialogTone = .success) { messages.append(message) }

    func reportFailure(title: String, message: String, symbol: String, recovery: String?) async -> Bool {
        failures += 1
        return false
    }
}

@main @MainActor
struct AppearanceCoordinatorTests {
    static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    static func main() async throws {
        _ = NSApplication.shared
        let suite = "nc-Appearance-coordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let store = AppearanceStore(defaults: defaults)
        let core = AppCore()
        let coordinator = AppearanceCoordinator(core: core, store: store, preferences: preferences)
        var refreshes = 0
        let controller = NotchcastModuleController(
            [.init(requires: [.appearance], module: coordinator)], preferences: preferences,
            modulesChanged: { refreshes += 1 })
        controller.run()
        precondition(coordinator.isEnabled && refreshes == 1)
        preferences.set(.island, false)
        await settle()
        precondition(store.isEnabled && coordinator.isEnabled && refreshes == 1)

        let dark = RaycastThemeCatalog.all.first { $0.appearance == .dark }!
        let light = RaycastThemeCatalog.all.first { $0.appearance == .light }!
        try store.select(dark, for: .dark)
        let first = NSWindow()
        let second = NSWindow()
        first.appearance = NSAppearance(named: .aqua)
        second.appearance = NSAppearance(named: .darkAqua)
        let firstOwner = UUID()
        let secondOwner = UUID()
        coordinator.preview(.theme(dark), owner: firstOwner, window: first)
        precondition(first.appearance?.name == .darkAqua && store.previewTarget == .theme(dark))
        coordinator.preview(.theme(light), owner: secondOwner, window: second)
        precondition(first.appearance?.name == .aqua && second.appearance?.name == .aqua)
        coordinator.endPreview(owner: firstOwner)
        precondition(store.previewTarget == .theme(light))
        coordinator.endPreview(owner: secondOwner)
        precondition(second.appearance?.name == .darkAqua && store.previewTarget == nil)
        precondition(store.dark == dark && store.light == nil)

        var parts = URLComponents()
        parts.scheme = "raycast"
        parts.host = "theme"
        parts.queryItems = [
            .init(name: "name", value: light.name), .init(name: "author", value: light.author),
            .init(name: "appearance", value: "light"),
            .init(name: "colors", value: light.colors.joined(separator: ",")),
            .init(name: "apply", value: "1")
        ]
        let url = parts.url!
        precondition(coordinator.handle(url))
        await settle()
        precondition(core.continuation != nil && store.light == nil)
        precondition(core.dialog.map(\.title) == ["Use Theme", "Just Add", "Cancel"] && core.defaultIndex == 0)
        core.answer(1)
        await settle()
        precondition(store.light == nil && store.imported.contains(light) && core.messages.last == "Theme Added")
        precondition(coordinator.handle(url))
        await settle()
        core.answer(0)
        await settle()
        precondition(store.light == light && core.messages.last == "Theme Applied")

        precondition(coordinator.handle(url))
        await settle()
        preferences.set(.appearance, false)
        await settle()
        precondition(!store.isEnabled && !coordinator.isEnabled && store.pendingImport == nil)
        precondition(refreshes == 2)
        let count = core.messages.count
        core.answer(0)
        await settle()
        precondition(core.messages.count == count && store.previewTarget == nil)
        coordinator.showThemes()
        precondition(core.paletteCoordinator.opened == nil)
        preferences.set(.appearance, true)
        await settle()
        coordinator.importLink("invalid")
        await settle()
        precondition(core.failures == 1)
        coordinator.showThemes()
        precondition(core.paletteCoordinator.opened == .theme)
        coordinator.preview(.theme(light), owner: firstOwner, window: first)
        core.palette.mode = .theme
        preferences.set(.appearance, false)
        await settle()
        precondition(first.appearance?.name == .aqua && store.previewTarget == nil && core.paletteCoordinator.popped)
        print("PASS: native dialog choices, untrusted apply, preview ownership, island independence and stale response rejection")
    }
}
