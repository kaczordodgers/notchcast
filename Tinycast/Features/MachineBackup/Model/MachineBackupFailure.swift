import Foundation

enum MachineBackupFailure: Error, Equatable {
    case disabled, configuration, busy, invalidSnapshot, invalidPath, unsafeTarget
    case targetExists, invalidResponse, outputLimit, toolFailed(Int32)
}
