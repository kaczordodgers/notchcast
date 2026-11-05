#if DEBUG && SETTINGS_TIMING_HARNESS
import AppKit
import SwiftUI

@MainActor final class AppCore {}
enum SettingsTab: String, Hashable {
    case general, about, notchcast
    init?(slug: String) { self.init(rawValue: slug) }
    var slug: String { rawValue }
}
@MainActor final class SettingsCoordinator {
    init(core: AppCore) {}
    func showSettings(tab: SettingsTab) {}
    func closeSettings() {}
}
@MainActor final class SettingsNavigationState {
    init(tab: SettingsTab) {}
    func select(_ tab: SettingsTab) {}
}
@MainActor final class SettingsEditorPresenter {
    init(core: AppCore, navigation: SettingsNavigationState) {}
}
struct SettingsDetailView: View {
    var body: some View { EmptyView() }
    func settingsEnvironment(core: AppCore, navigation: SettingsNavigationState,
                             editorPresenter: SettingsEditorPresenter) -> some View { self }
}
enum NotchcastFeature: CaseIterable {
    case sample
    var isWired: Bool { true }
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func set(_ feature: NotchcastFeature, _ enabled: Bool) {}
}
enum GalleryFailure: Error {
    case invalidRegistry
    case capture(String)
}
@MainActor struct GalleryPage {
    let name: String
    let types: [String]
    let makeWindow: () -> NSWindow
}
@MainActor enum GalleryPages {
    static func window(_ view: some View, size: CGSize, dark: Bool) -> NSWindow { NSWindow() }
}
@MainActor enum GalleryCapture {
    static func write(page: GalleryPage, window: NSWindow, output: URL) throws {}
}
#endif
