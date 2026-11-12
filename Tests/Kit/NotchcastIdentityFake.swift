import Foundation

struct NotchcastIdentity: Sendable {
    static let current = Self()
    private let suite = "notchcast-harness.\(UUID().uuidString)"
    func suiteName() -> String { suite }
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
}
