import Foundation

struct DownloadProgress: Codable, Sendable, Equatable {
    var fraction: Double?
    var received: Int64?
    var total: Int64?
    var bytesPerSecond: Double?
    var eta: TimeInterval?
    var stage: String?
}
