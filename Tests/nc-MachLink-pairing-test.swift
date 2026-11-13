// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift Tinycast/Features/MachLink/Service/*.swift
// notchcast-sources: Tinycast/Features/MachLink/AIUsageLinkModule.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift
import Foundation
import Network
import Observation

@MainActor protocol NotchcastModule {}

struct NotchcastIdentity {
    static let current = Self()
    func suiteName(suffix: String) -> String { "test" + suffix }
}

enum WebRules {
    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

@main @MainActor struct MachLinkPairingTest {
    static func main() throws {
        let suite = "mach-link-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let module = AIUsageLinkModule(defaults: defaults)
        for code in ["invalid", UUID().uuidString + ":!", UUID().uuidString + ":YQ=="] {
            do {
                _ = try module.pair(code: code)
                preconditionFailure("Invalid pairing accepted")
            } catch MachLinkMessage.Failure.invalidPairing {}
            precondition(defaults.string(forKey: "pairingID") == nil && !module.isPaired)
        }
        let code = try module.pair(code: "")
        precondition(module.isPaired && defaults.string(forKey: "pairingID") != nil)
        let imported = try module.pair(code: code)
        precondition(imported == code)
        try module.unpair()
        precondition(!module.isPaired && module.channel.pairing == nil)
        precondition(defaults.string(forKey: "pairingID") == nil)
        try module.unpair()
        let channel = module.channel
        nonisolated(unsafe) var endpointChanged = false
        withObservationTracking { _ = channel.peer } onChange: { endpointChanged = true }
        channel.endpoint = .hostPort(host: "localhost", port: 12345)
        precondition(endpointChanged, "Peer status did not observe endpoint changes")
        nonisolated(unsafe) var peersChanged = false
        withObservationTracking { _ = channel.manager.peers } onChange: { peersChanged = true }
        channel.manager.stop()
        precondition(peersChanged, "Peer discovery state is not observable")
        print("PASS pairing rejection, round trip, unpair and peer observation")
    }
}
