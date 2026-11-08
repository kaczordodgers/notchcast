import Foundation
import OSLog

@MainActor
final class KatanaModule: NotchcastModule {
    let client: KatanaClient
    private let transport: KatanaMIDITransport
    private var index: AgentActionIndex?
    let audio = KatanaAudioService()
    let tones = KatanaToneStore(file: NotchcastIdentity.current.applicationSupport()
        .appending(path: "Katana/tones.json"))

    init(midi: any KatanaMIDILayer = KatanaCoreMIDI()) {
        transport = KatanaMIDITransport(midi: midi)
        client = KatanaClient(transport: transport)
    }

    func configure(index: AgentActionIndex) {
        self.index = index
        if client.isEnabled { register() }
    }

    private func register() {
        guard let index else { return }
        unregister()
        do { try AgentDeviceActions.register(.katana, backend: self, in: index) } catch {
            Logger(subsystem: NotchcastIdentity.releaseFallbackSubsystem, category: "Katana")
                .error("Action registration failed: \(error.localizedDescription, privacy: .public)")
            unregister()
        }
    }

    private func unregister() {
        let ids = ["device.katana"] + AgentDeviceActions.Device.katana.operations.map { "device.katana.\($0)" }
        for id in ids { index?.unregister(id) }
    }

    func start() {
        transport.start()
        client.start()
        audio.start()
        register()
    }

    func stop() {
        unregister()
        client.stop()
        transport.stop()
        audio.stop()
    }
}

extension KatanaModule: AgentDeviceBackend {
    var isAvailable: Bool { client.isConnected }

    func readState() async throws -> AgentJSON {
        try await client.refresh()
        return .object(["channel": client.channel.map { .number(Double($0.rawValue)) } ?? .null,
                        "tone": client.toneName.map { .string($0) } ?? .null])
    }

    func perform(_ operation: String, parameters: AgentJSON) async throws -> AgentJSON {
        guard case .object(let fields) = parameters,
              case .number(let value)? = fields["channel"],
              [0, 1, 2, 5, 6].contains(value),
              let channel = KatanaChannel(rawValue: UInt8(value)) else { throw AgentReply.Code.badRequest }
        switch operation {
        case "channel": try await client.selectChannel(channel)
        case "tone":
            guard case .string(let id)? = fields["toneID"] else { throw AgentReply.Code.badRequest }
            try await tones.refresh()
            try Task.checkCancellation()
            guard let tone = tones.tones.first(where: { $0.name == id }) else { throw AgentReply.Code.badRequest }
            try await client.loadTone(tone, to: channel)
        default: throw AgentReply.Code.badRequest
        }
        return .object(["channel": .number(value)])
    }
}
