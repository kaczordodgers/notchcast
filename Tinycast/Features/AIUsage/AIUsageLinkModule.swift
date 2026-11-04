import Foundation
import Observation
import SystemConfiguration

@MainActor
@Observable
final class AIUsageLinkModule: NotchcastModule {
    let channel = MachLinkUsagePeerChannel()
    private(set) var isRunning = false
    private(set) var isPaired = false
    private(set) var failed = false
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let provider: AIUsageProvider
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets = KeychainSecretStore(scope: "mach-link")

    init(
        preferences: NotchcastPreferences = .shared,
        provider: AIUsageProvider = AIUsageProvider(
            cacheDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3/caches")),
        defaults: UserDefaults = UserDefaults(suiteName:
            (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".mach-link")!
    ) {
        self.preferences = preferences
        self.provider = provider
        self.defaults = defaults
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
        channel.pairing = pairing
        defaults.set(pairing.id.uuidString, forKey: "pairingID")
        try listen()
        return pairing.id.uuidString + ":" + pairing.secret.base64EncodedString()
    }

    func unpair() throws {
        if let pairing = channel.pairing { try secrets.removeSecret(for: pairing.id) }
        channel.manager.stop()
        channel.pairing = nil
        defaults.removeObject(forKey: "pairingID")
        isPaired = false
    }

    private func listen() throws {
        isPaired = channel.pairing != nil
        guard isRunning, let pairing = channel.pairing else { return }
        let provider = provider
        let preferences = preferences
        let name = SCDynamicStoreCopyLocalHostName(nil) as String? ?? UUID().uuidString
        try channel.manager.start(pairing: pairing, name: name) { request in
            if request.method == "link-health" {
                _ = try request.value(as: Bool.self)
                return try MachLinkMessage(id: request.id, method: request.method, value: true)
            }
            guard await preferences.isOn(.aiUsage), await preferences.isOn(.aiUsageOtherMac) else {
                throw MachLinkMessage.Failure.disconnected
            }
            let response = try await MachLinkUsagePeerChannel.response(to: request, provider: provider)
            try Task.checkCancellation()
            guard await preferences.isOn(.aiUsage), await preferences.isOn(.aiUsageOtherMac) else {
                throw MachLinkMessage.Failure.disconnected
            }
            return response
        }
        failed = false
    }
}
