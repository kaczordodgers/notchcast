import Foundation
import OSLog

@MainActor
final class KatanaModule: NotchcastModule {
    let client: KatanaClient
    private let transport: KatanaMIDITransport
    private var index: AgentActionIndex?
    let audio = KatanaAudioService()
    let tones = KatanaToneStore(file: URL.applicationSupportDirectory
        .appending(path: NotchcastIdentity.current.bundleID)
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
        do { try AgentDeviceActions.register(self, in: index) } catch {
            Logger(subsystem: NotchcastIdentity.current.bundleID, category: "Katana")
                .error("Action registration failed: \(error.localizedDescription, privacy: .public)")
            unregister()
        }
    }

    private func unregister() {
        if let index { AgentDeviceActions.unregister(self, from: index) }
    }

    func start() {
        transport.start()
        client.start()
        audio.start()
        register()
    }

    func stop() { shutdown() }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async { if phase == .beforeMacUpdate { shutdown() } }

    private func shutdown() {
        unregister()
        client.stop()
        transport.stop()
        audio.stop()
    }
}

extension KatanaModule: AgentDeviceBackend {
    var deviceName: String { "katana" }

    var operations: [(name: String, parameters: AgentParameterSchema)] {
        let channel = AgentParameterSchema.Property(kind: .integer,
            allowedValues: KatanaChannel.allCases.map { .number(Double($0.rawValue)) })
        return [("channel", .init(properties: ["channel": channel], required: ["channel"])),
                ("tone", .init(properties: ["toneID": .init(kind: .string, minimumLength: 1), "channel": channel],
                               required: ["toneID", "channel"]))]
    }

    var isAvailable: Bool { client.isConnected }

    func readState() async throws -> AgentJSON {
        try await client.refresh()
        return .object(["channel": client.channel.map { .number(Double($0.rawValue)) } ?? .null,
                        "tone": client.toneName.map { .string($0) } ?? .null])
    }

    func perform(_ operation: String, parameters: AgentJSON) async throws -> AgentJSON {
        guard case .object(let fields) = parameters,
              case .number(let value)? = fields["channel"],
              let channel = KatanaChannel.allCases.first(where: { Double($0.rawValue) == value })
        else { throw AgentReply.Code.badRequest }
        switch operation {
        case "channel": try await client.selectChannel(channel)
        case "tone":
            guard case .string(let id)? = fields["toneID"] else { throw AgentReply.Code.badRequest }
            try await tones.refresh()
            try Task.checkCancellation()
            try await client.loadTone(Self.tone(named: id, in: tones.tones), to: channel)
        default: throw AgentReply.Code.badRequest
        }
        return .object(["channel": .number(value)])
    }

    /// A name two imported tones share is refused rather than resolved to whichever comes first.
    nonisolated static func tone(named id: String, in tones: [KatanaTone]) throws -> KatanaTone {
        let matches = tones.filter { $0.name == id }
        guard matches.count == 1 else { throw AgentReply.Code.badRequest }
        return matches[0]
    }
}
