import Foundation

struct MicrophoneInput: Equatable, Sendable {
    struct Level: Codable, Equatable, Sendable {
        let element: UInt32
        let value: Float
    }

    enum Control: Sendable {
        case mute
        case volume
    }

    enum Failure: Error, Equatable, Sendable {
        case noInputs
        case read(Int32)
        case write(String, Int32)
        case unavailable(String)
        case unsupported(String)
        case changedControls(String)
        case invalidSavedLevels
    }

    let id: UInt32
    let uid: String
    var mute: [Level]
    var volume: [Level]

    var isMuted: Bool {
        (!mute.isEmpty && mute.allSatisfy { $0.value != 0 })
            || (!volume.isEmpty && volume.allSatisfy { $0.value == 0 })
    }

    static func valid(_ levels: [Level]) -> Bool {
        !levels.isEmpty && Set(levels.map(\.element)).count == levels.count
            && levels.allSatisfy { $0.value.isFinite && (0...1).contains($0.value) }
    }
}
