import Foundation

struct MachineSetupProfile: Codable, Equatable, Sendable {
    let format: Int
    let appVersion: String
    let backup: Data
    let tweaks: [String]
    let files: [String: [String: String]]
    let modules: [String: String]
}
