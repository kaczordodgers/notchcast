import Foundation

struct InUseReading: Equatable, Sendable {
    var camera = false
    var microphone = false
    var micApps: [String] = []
}
