import Foundation

enum DownloadState: String, Codable, Sendable {
    case waiting, running, done, failed, cancelled, interrupted

    var isFinished: Bool { self != .waiting && self != .running }
}
