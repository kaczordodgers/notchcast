import Foundation

struct DownloadJob: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: String
    var source: String
    var title: String
    var group: String?
    var state: DownloadState = .waiting
    var progress: DownloadProgress?
    var output: String?
    var detail: String?
    var created: Date
    var finished: Date?
    var options: [String: String] = [:]
    var usesIPhone: Bool { options["usesIPhone"] == "true" }
}
