import Foundation

enum DownloadState: String, Codable, Sendable {
    case held, waiting, running, done, failed, cancelled, interrupted

    /// A held job stays out of the run order until its kind is released.
    var isDue: Bool { self == .waiting || self == .running }
    var isFinished: Bool { self != .held && !isDue }
}
