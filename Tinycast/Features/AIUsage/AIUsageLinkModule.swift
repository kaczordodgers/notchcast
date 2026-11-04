import Foundation
import Observation
import SystemConfiguration

@MainActor
@Observable
final class AIUsageLinkModule: NotchcastModule {
    let channel = MachLinkUsagePeerChannel()
    @ObservationIgnored var listenerRoute: (@Sendable (MachLinkMessage) async throws -> MachLinkMessage?)?
    private(set) var isRunning = false
    private(set) var isPaired = false
    private(set) var failed = false
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let provider: AIUsageProvider?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets = KeychainSecretStore(scope: "mach-link")

    init(
        preferences: NotchcastPreferences = .shared,
        provider: AIUsageProvider? = nil,
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
        try channel.manager.start(pairing: pairing, name: name) { [weak self] request in
            guard let self else { throw MachLinkMessage.Failure.disconnected }
            return try await self.respond(to: request)
        }
        failed = false
    }

    func respond(to request: MachLinkMessage) async throws -> MachLinkMessage {
        if request.method == "dialogs" {
            guard preferences.isOn(.machBlockedDialogAlert) else {
                throw MachLinkMessage.Failure.disconnected
            }
            return try MachLinkMessage(id: request.id, method: request.method,
                value: BlockedDialogWindows.current())
        }
        if let response = try await listenerRoute?(request) { return response }
        if request.method == "link-health" {
            _ = try request.value(as: Bool.self)
            return try MachLinkMessage(id: request.id, method: request.method, value: true)
        }
        guard preferences.isOn(.aiUsage), preferences.isOn(.aiUsageOtherMac) else {
            throw MachLinkMessage.Failure.disconnected
        }
        let path = preferences.aiUsageCachePath
        let provider = provider ?? AIUsageProvider(cacheDirectory: AIUsageProvider.cacheDirectory(
            path: path, homeDirectory: FileManager.default.homeDirectoryForCurrentUser))
        let response = try await MachLinkUsagePeerChannel.response(to: request, provider: provider)
        try Task.checkCancellation()
        guard preferences.isOn(.aiUsage), preferences.isOn(.aiUsageOtherMac) else {
            throw MachLinkMessage.Failure.disconnected
        }
        return response
    }

}
