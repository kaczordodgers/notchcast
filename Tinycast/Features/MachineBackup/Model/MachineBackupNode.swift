import Foundation

struct MachineBackupNode: Decodable, Sendable, Equatable {
    let name: String
    let path: String
    let type: String
    let size: UInt64?
}
