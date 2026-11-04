import Foundation

enum DialogTone { case success, danger, neutral }
enum DialogAction { enum Role { case `default` } }
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
    func showMessage(_ message: String, tone: DialogTone) { fatalError("Inject message reporting") }
    func confirm(title: String, message: String?, symbol: String?, confirmTitle: String,
                 tone: DialogTone, confirmRole: DialogAction.Role) async -> Bool {
        fatalError("Inject confirmation")
    }
}
