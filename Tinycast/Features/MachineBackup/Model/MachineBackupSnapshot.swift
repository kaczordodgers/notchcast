import Foundation

struct MachineBackupSnapshot: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let time: String
    let hostname: String
    let paths: [String]
}
