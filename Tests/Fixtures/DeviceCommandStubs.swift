import Foundation

enum SettingsTab: Sendable { case notchcast }
struct AppEntry {
    enum Kind { case command }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    let settingsOwner: SettingsTab?
    let symbolName: String
}
@MainActor final class AppCore {
    static let shared = AppCore()
    func showMessage(_ message: String) { fatalError("Inject message reporting") }
}
