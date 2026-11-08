import Foundation
import Observation

@MainActor
@Observable
final class KatanaClient {
    private(set) var channel: KatanaChannel?
    private(set) var toneName: String?
    private(set) var audioSettings: KatanaAudioSettings?
    private(set) var isEnabled = false
    @ObservationIgnored private let transport: (any KatanaTransport)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private let backupDirectory: URL
    @ObservationIgnored private let ampLock: KatanaAmpLock

    init(transport: (any KatanaTransport)? = nil,
         backupDirectory: URL = NotchcastIdentity.current.applicationSupport()
            .appending(path: "Katana/backups"),
         lockPath: String = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".katana-venv/amp.lock").path,
         lockTimeout: Duration = .seconds(10)) {
        self.transport = transport
        self.backupDirectory = backupDirectory
        ampLock = KatanaAmpLock(path: lockPath, timeout: lockTimeout)
    }

    var isConnected: Bool { isEnabled && transport?.connectionID != nil }

    func start() { isEnabled = true }

    func stop() {
        isEnabled = false
        generation = UUID()
        channel = nil
        toneName = nil
        audioSettings = nil
    }

    func refresh() async throws {
        try await perform { context in
            let bytes = try await self.read(KatanaSysEx.activeChannel, count: 2, context: context)
            guard bytes[0] == 0, let channel = KatanaChannel(rawValue: bytes[1]) else { throw KatanaError.invalidData }
            let name = try await self.read(0x20000000, count: 16, context: context)
            self.channel = channel
            self.toneName = KatanaSysEx.name(name)
        }
    }

    func selectChannel(_ target: KatanaChannel) async throws {
        try await perform { context in try await self.select(target, context: context) }
    }

    func loadTone(_ tone: KatanaTone, to target: KatanaChannel) async throws {
        try await perform { context in
            if target != .panel { try await self.backup(target, context: context) }
            try await self.select(target, context: context)
            for region in tone.regions {
                try await self.writeRegion(region.region, bytes: region.bytes, context: context)
            }
            try await self.writeRegion(0x1C, bytes: tone.knob, page: 1, context: context)
            try await self.writeRegion(0x1E, bytes: tone.knobSolo, page: 1, context: context)
            if target != .panel {
                try await self.write(KatanaSysEx.patchWrite, [0, target.rawValue], context: context)
                do {
                    try await self.write(KatanaSysEx.previewMute, [1], context: context)
                    try await self.write(KatanaSysEx.export, [0x40, target.rawValue], context: context)
                } catch {
                    try await self.unmute(context: context)
                    throw error
                }
                try await self.unmute(context: context)
            }
            self.toneName = tone.name
        }
    }

    func refreshAudioSettings() async throws {
        try await perform { context in
            self.audioSettings = try await KatanaAudioSettings(bytes: self.read(
                KatanaSysEx.usbSettings, count: 5, context: context))
        }
    }

    func setAudioSettings(_ settings: KatanaAudioSettings) async throws {
        try await perform { context in
            try await self.write(KatanaSysEx.usbSettings, settings.bytes, context: context)
            let bytes = try await self.read(KatanaSysEx.usbSettings, count: 5, context: context)
            guard bytes == settings.bytes else { throw KatanaError.verificationFailed }
            self.audioSettings = settings
        }
    }

    private struct Context {
        let generation: UUID
        let connection: UUID
        let transport: any KatanaTransport
    }

    private func perform(_ action: @MainActor (Context) async throws -> Void) async throws {
        guard isEnabled else { throw KatanaError.disabled }
        guard operation == nil else { throw KatanaError.busy }
        guard let transport, let connection = transport.connectionID else {
            channel = nil
            toneName = nil
            audioSettings = nil
            throw KatanaError.unavailable
        }
        let id = UUID()
        operation = id
        defer { if operation == id { operation = nil } }
        let context = Context(generation: generation, connection: connection, transport: transport)
        do {
            let descriptor = try await ampLock.acquire()
            defer { ampLock.release(descriptor) }
            try await write(0x7F000001, [1], context: context)
            try await action(context)
        } catch {
            if generation == context.generation {
                channel = nil
                toneName = nil
                audioSettings = nil
            }
            throw error
        }
    }

    private func unmute(context: Context) async throws {
        let recovery = Task { @MainActor in
            guard context.transport.connectionID == context.connection else { return }
            try await context.transport.send(KatanaSysEx.write(KatanaSysEx.previewMute, [0]))
        }
        try await recovery.value
    }

    private func isCurrent(_ context: Context) -> Bool {
        isEnabled && generation == context.generation && context.transport.connectionID == context.connection
    }

    private func exchange(_ packet: [UInt8], context: Context) async throws -> KatanaSysEx.Message {
        try Task.checkCancellation()
        guard isCurrent(context) else { throw CancellationError() }
        let response = try await context.transport.exchange(packet)
        try Task.checkCancellation()
        guard isCurrent(context) else { throw CancellationError() }
        let message = try KatanaSysEx.decode(response)
        guard message.command == 0x12 else { throw KatanaError.invalidData }
        return message
    }

    private func read(_ address: Int, count: Int, context: Context) async throws -> [UInt8] {
        let message = try await exchange(KatanaSysEx.read(address, count: count), context: context)
        guard message.address == address, message.data.count == count else { throw KatanaError.verificationFailed }
        return message.data
    }

    private func write(_ address: Int, _ bytes: [UInt8], context: Context) async throws {
        if address != KatanaSysEx.patchWrite && address != KatanaSysEx.export {
            try Task.checkCancellation()
            guard isCurrent(context) else { throw CancellationError() }
            try await context.transport.send(KatanaSysEx.write(address, bytes))
            try Task.checkCancellation()
            guard isCurrent(context) else { throw CancellationError() }
            return
        }
        let message = try await exchange(KatanaSysEx.write(address, bytes), context: context)
        guard message.address == address, message.data == bytes else { throw KatanaError.verificationFailed }
    }

    private func backup(_ target: KatanaChannel, context: Context) async throws {
        let slot = Int(target.rawValue + 1) * 0x10
        func region(_ region: UInt8, count: Int, page: Int = 0) async throws -> [UInt8] {
            var bytes: [UInt8] = []
            for offset in stride(from: 0, to: count, by: 128) {
                let high = slot + page
                let address = KatanaSysEx.patchAddress(region: region, offset: offset)
                    + ((high >> 7) << 24) + ((high & 0x7F) << 16)
                bytes += try await read(address, count: min(128, count - offset), context: context)
            }
            return bytes
        }
        var regions: [KatanaTone.Region] = []
        for known in KatanaPatchRegion.all {
            regions.append(try await .init(region: known.region, bytes: region(known.region, count: known.length)))
        }
        let tone = try await KatanaTone(regions: regions, knob: region(0x1C, count: 5, page: 1),
                                       knobSolo: region(0x1E, count: 1, page: 1))
        let file = backupDirectory.appending(path: "\(target.rawValue)-\(UUID().uuidString).json")
        try await KatanaToneRepository.backup(tone, to: file)
        try Task.checkCancellation()
        guard isCurrent(context) else { throw CancellationError() }
    }

    private func select(_ target: KatanaChannel, context: Context) async throws {
        channel = nil
        toneName = nil
        try await write(KatanaSysEx.selectChannel, [0, target.rawValue], context: context)
        for _ in 0..<8 {
            let active = try await read(KatanaSysEx.activeChannel, count: 2, context: context)
            if active == [0, target.rawValue] {
                let name = try await read(0x20000000, count: 16, context: context)
                channel = target
                toneName = KatanaSysEx.name(name)
                return
            }
        }
        throw KatanaError.verificationFailed
    }

    private func writeRegion(_ region: UInt8, bytes: [UInt8], page: Int = 0, context: Context) async throws {
        for offset in stride(from: 0, to: bytes.count, by: 128) {
            let chunk = Array(bytes[offset..<min(offset + 128, bytes.count)])
            let address = KatanaSysEx.patchAddress(region: region, offset: offset, page: page)
            try await write(address, chunk, context: context)
            let readback = try await read(address, count: chunk.count, context: context)
            for (index, value) in chunk.enumerated() {
                if page == 0, region == 0x3E, [0, 7].contains(offset + index) { continue }
                guard readback[index] == value else { throw KatanaError.verificationFailed }
            }
        }
    }
}
