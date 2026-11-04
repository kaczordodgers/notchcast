import Foundation

protocol FleetThreadSource: Sendable {
    func read(_ destination: FleetSnapshot.Destination) async throws -> FleetSnapshot
}
