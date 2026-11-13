// notchcast-sources: Tinycast/Features/FleetPanel/Model/FleetSnapshot.swift
import Foundation

private struct OldSnapshot: Codable {
    enum Failure: String, Codable { case off, failed }
    let rows: [FleetSnapshot.Row]
    let failure: Failure?
}

@main struct FleetWireTest {
    static func main() throws {
        let payload = try JSONEncoder().encode(FleetSnapshot(rows: [], failure: .sourceOff))
        let old = try JSONDecoder().decode(OldSnapshot.self, from: payload)
        precondition(old.failure == .off && old.rows.isEmpty)
        let roundTrip = try JSONDecoder().decode(FleetSnapshot.self, from: payload)
        precondition(roundTrip.failure == .sourceOff)
        for failure: OldSnapshot.Failure in [.off, .failed] {
            let oldPayload = try JSONEncoder().encode(OldSnapshot(rows: [], failure: failure))
            let current = try JSONDecoder().decode(FleetSnapshot.self, from: oldPayload)
            precondition(current.failure?.rawValue == failure.rawValue)
        }
        print("PASS old decoder reads new payload; new decoder reads old payload")
    }
}
