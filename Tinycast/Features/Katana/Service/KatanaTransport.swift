import Foundation

@MainActor
protocol KatanaTransport: AnyObject {
    var connectionID: UUID? { get }
    func send(_ packet: [UInt8]) async throws
    func exchange(_ packet: [UInt8]) async throws -> [UInt8]
}
