import Foundation

protocol MachineBackupTooling: Sendable {
    func run(_ request: MachineBackupRequest) async throws -> Data
}
