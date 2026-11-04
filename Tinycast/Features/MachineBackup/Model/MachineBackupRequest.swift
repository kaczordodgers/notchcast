import Foundation

struct MachineBackupRequest: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    var environment: [String: String] = [:]
    var restoreTarget: URL?
    var homeDirectory: URL?
}
