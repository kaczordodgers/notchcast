import Foundation

nonisolated struct SpotlightIndexing: Equatable, Sendable {
    enum State: Equatable, Sendable { case enabled, disabled, unknown }
    let volumes: [String: State]
    var isOff: Bool { !volumes.isEmpty && volumes.values.allSatisfy { $0 == .disabled } }

    static func parse(_ output: String) -> Self {
        var volumes: [String: State] = [:]
        var current: String?
        for line in output.split(separator: "\n") {
            if line.hasSuffix(":"), line.first?.isWhitespace == false {
                let volume = String(line.dropLast())
                current = volume
                volumes[volume] = .unknown
            } else if let current {
                let text = line.lowercased()
                if text.contains("indexing enabled") { volumes[current] = .enabled }
                if text.contains("indexing disabled") || text.contains("indexing and searching disabled") {
                    volumes[current] = .disabled
                }
            }
        }
        return Self(volumes: volumes)
    }

    func needsTurnOff(featureEnabled: Bool) -> Bool {
        featureEnabled && volumes.values.contains(.enabled)
    }
}
