import Foundation

enum RemoteFanRequest: String, Codable, Sendable, CaseIterable {
    case status, cycle, auto, mid, max
}
