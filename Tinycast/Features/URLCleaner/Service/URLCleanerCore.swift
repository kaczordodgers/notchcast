import Foundation

extension NotchcastCore {
    static let urlCleaner = URLCleanerModule(defaults: UserDefaults(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast") + ".urlCleaner"))
}
