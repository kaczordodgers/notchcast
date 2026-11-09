import Foundation
import Observation
import SystemConfiguration

@MainActor
@Observable
final class AIUsageLinkModule: NotchcastModule {
    let channel = MachLinkChannel()
    private(set) var isRunning = false
    private(set) var isPaired = false
    private(set) var failed = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets = KeychainSecretStore(scope: "mach-link")

    init(defaults: UserDefaults = UserDefaults(suiteName:
        NotchcastIdentity.current.suiteName(suffix: ".mach-link"))!) {
        self.defaults = defaults
        channel.manager.register("link-health") { request in
            _ = try request.value(as: Bool.self)
            return try MachLinkMessage(id: request.id, method: request.method, value: true)
        }
    }

    func start() {
        isRunning = true
        do {
            if let raw = defaults.string(forKey: "pairingID"), let id = UUID(uuidString: raw) {
                channel.pairing = try MachLinkPairing.load(id: id, from: secrets)
            }
            try listen()
        } catch { failed = true }
    }

    func stop() {
        isRunning = false
        channel.manager.stop()
        channel.pairing = nil
    }

    func pair(code: String) throws -> String {
        let pairing: MachLinkPairing
        if code.isEmpty {
            pairing = try .create()
        } else {
            let parts = code.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
                  let secret = Data(base64Encoded: String(parts[1])) else {
                throw MachLinkMessage.Failure.invalidPairing
            }
            pairing = try MachLinkPairing(id: id, secret: secret)
        }
        try pairing.save(to: secrets)
        channel.manager.stop()
        channel.pairing = isRunning ? pairing : nil
        defaults.set(pairing.id.uuidString, forKey: "pairingID")
        isPaired = true
        try listen()
        return pairing.id.uuidString + ":" + pairing.secret.base64EncodedString()
    }

    func unpair() throws {
        if let raw = defaults.string(forKey: "pairingID"), let id = UUID(uuidString: raw) {
            try secrets.removeSecret(for: id)
        }
        channel.manager.stop()
        channel.pairing = nil
        defaults.removeObject(forKey: "pairingID")
        isPaired = false
    }

    private func listen() throws {
        isPaired = isPaired || channel.pairing != nil
        guard isRunning, let pairing = channel.pairing else { return }
        let name = SCDynamicStoreCopyLocalHostName(nil) as String? ?? UUID().uuidString
        try channel.manager.start(pairing: pairing, name: name)
        failed = false
    }
}
