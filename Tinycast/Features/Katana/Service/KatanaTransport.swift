import Foundation

@MainActor
protocol KatanaTransport: AnyObject {
    var connectionID: UUID? { get }
    func exchange(_ packet: [UInt8]) async throws -> [UInt8]
}
