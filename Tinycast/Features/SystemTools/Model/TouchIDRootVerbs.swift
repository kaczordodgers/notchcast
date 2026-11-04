import Foundation

nonisolated enum TouchIDRootVerbs: String, Sendable, CaseIterable {
    case enableSudoTouchID, disableSudoTouchID

    var destination: String { "/etc/pam.d/sudo_local" }
    var owner: String { "root:wheel" }
    var mode: UInt16 { 0o444 }

    func replacement(sudo: String, local: String?) throws -> String {
        try TouchIDPolicy.replacement(sudo: sudo, local: local, enabled: self == .enableSudoTouchID)
    }
}
