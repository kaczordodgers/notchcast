import Foundation

extension MachLinkChannel {
    func probeHealth() async throws -> Duration {
        let start = ContinuousClock.now
        guard try await request(true, method: MachLinkMethod.linkHealth.rawValue, timeout: .seconds(2), as: Bool.self) else {
            throw MachLinkMessage.Failure.disconnected
        }
        return start.duration(to: .now)
    }
}
