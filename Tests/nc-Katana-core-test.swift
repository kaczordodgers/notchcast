// notchcast-reads: notchcast/docs/katana.md
// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift

// notchcast-sources: Tinycast/Features/Katana/KatanaModule.swift
// notchcast-sources: Tinycast/Features/Katana/KatanaModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift

// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift

// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift

// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
import Foundation
import Darwin

@MainActor
final class FakeKatanaTransport: KatanaTransport {
    var connectionID: UUID? = UUID()
    var packets: [KatanaSysEx.Message] = []
    var memory: [Int: [UInt8]] = [0: [0, 1], 0x20000000: Array("CLEAN           ".utf8)]
    var staleReads = 0
    var refuse: Int?
    var corruptRead: Int?
    var pause: CheckedContinuation<Void, Never>?
    var pauseNext = false
    var pauseAddress: Int?

    func send(_ packet: [UInt8]) async throws {
        _ = try await respond(packet)
    }

    func exchange(_ packet: [UInt8]) async throws -> [UInt8] {
        let message = try KatanaSysEx.decode(packet)
        guard message.command == 0x11 || [KatanaSysEx.patchWrite, KatanaSysEx.export].contains(message.address)
        else { fatalError("Command has no echo") }
        return try await respond(packet)
    }

    private func respond(_ packet: [UInt8]) async throws -> [UInt8] {
        let message = try KatanaSysEx.decode(packet)
        packets.append(message)
        if pauseNext || pauseAddress == message.address {
            pauseNext = false
            pauseAddress = nil
            await withCheckedContinuation { pause = $0 }
        }
        try Task.checkCancellation()
        if message.address == refuse { throw KatanaError.verificationFailed }
        if message.command == 0x12 {
            memory[message.address] = message.data
            if message.address == KatanaSysEx.selectChannel { memory[0] = message.data }
            return packet
        }
        let count = message.data.reduce(0) { ($0 << 7) | Int($1) }
        if message.address == 0, staleReads > 0 {
            staleReads -= 1
            return try KatanaSysEx.write(0, [0, 0])
        }
        var bytes = memory[message.address] ?? Array(repeating: 0, count: count)
        if message.address >= 0x20100000, message.address < 0x22000000 {
            let region = UInt8((message.address >> 8) & 0x7F)
            let offset = Int(message.address & 0x7F)
            let defaults = KatanaGen3Defaults.image()[region] ?? []
            if defaults.count >= offset + count { bytes = Array(defaults[offset..<(offset + count)]) }
        }
        if message.address == corruptRead { bytes[0] ^= 1 }
        return try KatanaSysEx.write(message.address, bytes)
    }
}

@MainActor
final class FakeKatanaAudio: KatanaAudioTransport {
    var connectionID: UUID? = UUID()
    var isUSB = true
    var destination: KatanaRecording.Destination?
    var stops = 0
    var failFinish = false

    func drySamples() async throws -> (samples: [Float], sampleRate: Double) {
        (sine(110), 44_100)
    }

    func beginRecording(_ destination: KatanaRecording.Destination) async throws { self.destination = destination }

    func finishRecording() async throws -> KatanaRecording {
        guard !failFinish, let destination else { throw KatanaError.verificationFailed }
        return KatanaRecording(wet: destination.wet, dry: destination.dry, sampleRate: 44_100, frames: 88_200)
    }

    func stop() { stops += 1 }
}

func sine(_ frequency: Double, sampleRate: Double = 44_100, count: Int = 4096) -> [Float] {
    (0..<count).map { Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate) * 0.2) }
}

@main
@MainActor
struct KatanaTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do {
            guard try condition() else { fatalError(message) }
        } catch { fatalError("\(message): \(error)") }
    }

    @MainActor
    static func rejects(_ expected: KatanaError, _ action: () async throws -> Void) async {
        do {
            try await action()
            fatalError("Expected \(expected)")
        } catch {
            expect(error as? KatanaError == expected, "Wrong error: \(error)")
        }
    }

    @MainActor
    static func main() async throws {
        try framing()
        try imports()
        try pitch()
        try await client()
        try await lockTransactions()
        try await audio()
        try await repository()
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(filePath: path)
            let tones = try KatanaToneImporter.read(Data(contentsOf: url), fileExtension: url.pathExtension)
            expect(!tones.isEmpty, "Reference file \(url.lastPathComponent)")
        }
        print("Katana: \(checks) checks passed; fake MIDI/audio only")
    }

    static func lockTransactions() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let fake = FakeKatanaTransport()
        let client = KatanaClient(transport: fake, lockPath: file.path, lockTimeout: .milliseconds(220))
        client.start()
        try await client.refresh()
        expect(!FileManager.default.fileExists(atPath: file.path), "Missing lock stays missing")
        try Data().write(to: file)
        let other = open(file.path, O_RDWR)
        guard other >= 0 else { fatalError("Open test lock") }
        defer { close(other) }
        expect(flock(other, LOCK_EX | LOCK_NB) == 0, "Hold external lock")
        let count = fake.packets.count
        let start = ContinuousClock.now
        await rejects(.ampBusy) { try await client.refresh() }
        expect(start.duration(to: .now) >= .milliseconds(220), "Busy waits for deadline")
        expect(fake.packets.count == count, "Busy sends no MIDI")
        let waiting = Task { try await client.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        expect(fake.packets.count == count, "Waiting sends no MIDI")
        flock(other, LOCK_UN)
        try await waiting.value
        expect(flock(other, LOCK_EX | LOCK_NB) == 0, "Success releases lock")
        flock(other, LOCK_UN)
        fake.refuse = 0
        await rejects(.verificationFailed) { try await client.refresh() }
        expect(flock(other, LOCK_EX | LOCK_NB) == 0, "Failure releases lock")
        let cancelledWait = Task { try await client.refresh() }
        try await Task.sleep(for: .milliseconds(30))
        cancelledWait.cancel()
        do { try await cancelledWait.value; fatalError("Wait cancellation accepted") } catch is CancellationError {}
        flock(other, LOCK_UN)
        fake.refuse = nil
        fake.pauseNext = true
        let cancelled = Task { try await client.refresh() }
        while fake.pause == nil { await Task.yield() }
        expect(flock(other, LOCK_EX | LOCK_NB) != 0, "MIDI transaction holds lock")
        cancelled.cancel()
        fake.pause?.resume()
        fake.pause = nil
        do { try await cancelled.value; fatalError("Transaction cancellation accepted") } catch is CancellationError {}
        expect(flock(other, LOCK_EX | LOCK_NB) == 0, "Cancellation releases lock")
        flock(other, LOCK_UN)
        try await client.refresh()
        expect(FileManager.default.fileExists(atPath: file.path), "Existing lock is retained")
    }

    static func framing() throws {
        let packet = try KatanaSysEx.write(0x7F000100, [0, 5])
        expect(packet == [0xF0, 0x41, 0x10, 1, 5, 7, 0x12, 0x7F, 0, 1, 0, 0, 5, 0x7B, 0xF7], "Gen 3 wire bytes")
        expect(try KatanaSysEx.decode(packet).data == [0, 5], "Decode")
        let request = try KatanaSysEx.decode(KatanaSysEx.read(0x20001C00, count: 128))
        expect(request.data == [0, 0, 1, 0], "7-bit size carry")
        expect(KatanaSysEx.patchAddress(region: 0x1C, offset: 128) == 0x20001D00, "Region carry")
        for bad in [Array(packet.dropLast()), [0xF0], Array(repeating: UInt8(0xFF), count: 20)] {
            expect((try? KatanaSysEx.decode(bad)) == nil, "Reject malformed SysEx")
        }
        var corrupt = packet
        corrupt[8] ^= 1
        expect((try? KatanaSysEx.decode(corrupt)) == nil, "Reject bad checksum")
        expect((try? KatanaSysEx.write(0, [0x80])) == nil, "Reject MIDI command injection")
        expect((try? KatanaAudioSettings(bytes: [20, 101, 25, 0, 50])) == nil, "USB range")
    }

    static func tone() throws -> KatanaTone {
        let regions = KatanaPatchRegion.all.map { known in
            KatanaTone.Region(region: known.region, bytes: KatanaGen3Defaults.image()[known.region]!)
        }
        return try KatanaTone(regions: regions, knob: [1, 2, 3, 4, 5], knobSolo: [0])
    }

    static func imports() throws {
        for value in [String(Int.min), String(Int.max), "-65536", "65536"] {
            let object: [String: Any] = ["name": "fixture", "raw": ["68": ["00"]],
                "set": ["reverb": ["time": value]]]
            let data = try JSONSerialization.data(withJSONObject: object)
            expect((try? KatanaToneImporter.read(data, fileExtension: "json")) == nil,
                   "Out-of-range string number rejected: \(value)")
        }
        let tone = try tone()
        let partial = try KatanaTone(regions: tone.regions.filter { KatanaPatchRegion.essential.contains($0.region) },
                                     knob: tone.knob, knobSolo: tone.knobSolo)
        expect(partial.regions.count == KatanaPatchRegion.all.count, "Omitted regions initialize before load")
        expect(partial.regions.first { $0.region == 0x28 }?.bytes == KatanaGen3Defaults.image()[0x28],
               "Partial tones cannot inherit a previous channel's effects")
        var image = [UInt8](repeating: 0, count: 73728)
        for region in tone.regions {
            image.replaceSubrange((Int(region.region) << 7)..<((Int(region.region) << 7) + region.bytes.count),
                                  with: region.bytes)
        }
        image[(1 << 14) + (0x1C << 7)] = 42
        let imported = try KatanaToneImporter.read(Data(image), fileExtension: "kat3")
        expect(imported[0].knob[0] == 42, "Knob page uses unpacked address")
        expect(imported[0].name == "KATANA", "Read Gen 3 image")
        var parameters: [String: [String]] = [:]
        for region in tone.regions {
            let block = KatanaPatchRegion.all.first { $0.region == region.region }!.block
            parameters["PATCH%\(block)"] = region.bytes.map { String(format: "%02X", $0) }
        }
        let liveset: [String: Any] = ["device": "KATANA Gen3", "data": [[
            ["paramSet": parameters], ["paramSet": parameters]]]]
        let data = try JSONSerialization.data(withJSONObject: liveset)
        expect(try KatanaToneImporter.read(data, fileExtension: "tsl").count == 2, "Every liveset patch")
        image[16] = 0x80
        expect((try? KatanaToneImporter.read(Data(image), fileExtension: "kat3")) == nil, "Reject injected bytes")
        expect((try? KatanaToneImporter.read(Data([1]), fileExtension: "kat2")) == nil, "Reject truncated legacy")
        expect(try JSONDecoder().decode(KatanaTone.self, from: JSONEncoder().encode(tone)) == tone, "Validated persistence")
        var mk2 = [UInt8](repeating: 0, count: 1992)
        for block in KatanaMkIIBlock.allCases {
            let bytes = KatanaLegacyFormats.decode(KatanaMk1Data.initial[block]!)
            mk2.replaceSubrange(block.fileOffset..<(block.fileOffset + block.size), with: bytes.prefix(block.size))
        }
        let legacy = try KatanaToneImporter.read(Data(mk2), fileExtension: "kat2")
        expect(legacy[0].converted && legacy[0].regions.count == tone.regions.count, "MkII conversion")
        var mk1 = [UInt8](repeating: 0, count: 2797)
        mk1.replaceSubrange(0..<16, with: Array("LEGACY          ".utf8))
        expect(try KatanaToneImporter.read(Data(mk1), fileExtension: "kat")[0].converted, "MkI conversion")
        let raw = Dictionary(uniqueKeysWithValues: tone.regions.map { region in
            (String(format: "%02X", region.region), region.bytes.map { String(format: "%02X", $0) })
        })
        let preset: [String: Any] = ["name": "TEST", "raw": raw, "set": [
            "amp": ["gain": 77, "type": "brown"],
            "delay1": ["time": 420], "reverb": ["time": 15], "modparam": ["acsim_low": -10]]]
        let parsed = try KatanaToneImporter.read(JSONSerialization.data(withJSONObject: preset), fileExtension: "json")[0]
        expect(parsed.name == "TEST", "Preset name overrides raw")
        expect(parsed.regions.first { $0.region == 6 }?.bytes[0] == 77, "Preset overlay wins")
        expect(parsed.regions.first { $0.region == 0x28 }?.bytes[1...4] == [0, 1, 10, 4], "Delay nibbles")
        expect(parsed.regions.first { $0.region == 0x34 }?.bytes[2] == 14, "Reverb bias")
        expect(parsed.regions.first { $0.region == 0x1C }?.bytes[194] == 40, "Effect offset carry and bias")
    }

    static func pitch() throws {
        for frequency in [82.4069, 110, 146.832, 196, 246.942, 329.628, 440] {
            let reading = KatanaPitchEngine.detect(sine(frequency), sampleRate: 44_100)
            expect(reading != nil && abs(reading!.frequency - frequency) < 0.2, "Pitch \(frequency)")
        }
        expect(KatanaPitchEngine.detect(Array(repeating: 0, count: 4096), sampleRate: 44_100) == nil, "Silence")
        expect(KatanaPitchEngine.detect([.nan], sampleRate: .infinity) == nil, "Nonfinite samples")
    }

    @MainActor
    static func client() async throws {
        let fake = FakeKatanaTransport()
        let backups = FileManager.default.temporaryDirectory.appending(path: "katana-backups-\(UUID())")
        defer { try? FileManager.default.removeItem(at: backups) }
        let client = KatanaClient(transport: fake, backupDirectory: backups)
        await rejects(.disabled) { try await client.selectChannel(.b1) }
        client.start()
        fake.staleReads = 2
        try await client.selectChannel(.b1)
        expect(client.channel == .b1, "Wait for matching channel")
        expect(fake.packets.filter { $0.address == KatanaSysEx.selectChannel }.count == 1, "One select write")
        fake.packets = []
        fake.refuse = 0x20200000
        await rejects(.verificationFailed) { try await client.loadTone(tone(), to: .a1) }
        expect(!fake.packets.contains { $0.address == KatanaSysEx.selectChannel
            || $0.address == KatanaSysEx.patchWrite }, "Incomplete backup prevents overwrite")
        fake.refuse = nil
        try await client.loadTone(tone(), to: .a2)
        let files = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        expect(files.count == 1, "Slot backup persisted before load")
        expect(try JSONDecoder().decode(KatanaTone.self, from: Data(contentsOf: files[0])).regions.count
               == KatanaPatchRegion.all.count, "Backup retains all regions")
        let backupRead = fake.packets.firstIndex { $0.address == 0x20300000 }!
        let firstWrite = fake.packets.firstIndex { $0.address == 0x20000000 && $0.command == 0x12 }!
        expect(backupRead < firstWrite, "Read stored slot before editing")
        expect(fake.packets.contains { $0.address == KatanaSysEx.export && $0.data == [0x40, 2] }, "Export acknowledgement")
        expect(fake.memory[0x20011C00] == [1, 2, 3, 4, 5], "Knob layer preserved")
        fake.packets = []
        try await client.loadTone(tone(), to: .panel)
        expect(!fake.packets.contains { $0.address == KatanaSysEx.patchWrite }, "Panel never receives PATCH_WRITE")
        fake.corruptRead = 0x20000600
        fake.packets = []
        await rejects(.verificationFailed) { try await client.loadTone(tone(), to: .a1) }
        expect(!fake.packets.contains { $0.address == KatanaSysEx.patchWrite }, "Mismatch prevents save")
        fake.corruptRead = nil
        fake.refuse = KatanaSysEx.export
        await rejects(.verificationFailed) { try await client.loadTone(tone(), to: .b2) }
        expect(fake.memory[KatanaSysEx.previewMute] == [0], "Failed export unmutes")
        fake.refuse = nil
        let settings = try KatanaAudioSettings(toEffectDecibels: -5, effectOutput: 50, mix: 25, loopback: false, dryOutput: 50)
        try await client.setAudioSettings(settings)
        expect(client.audioSettings == settings, "USB readback")
        fake.pauseNext = true
        let task = Task { try await client.selectChannel(.b1) }
        while fake.pause == nil { await Task.yield() }
        await rejects(.busy) { try await client.refresh() }
        client.stop()
        fake.pause?.resume()
        fake.pause = nil
        do { try await task.value; fatalError("Stale operation succeeded") } catch is CancellationError {}
        expect(client.channel == nil && !client.isEnabled, "Stop rejects stale result")
        let disconnected = KatanaClient(transport: KatanaMIDITransport(midi: SilentKatanaMIDI()))
        disconnected.start()
        await rejects(.unavailable) { try await disconnected.refresh() }
        client.start()
        fake.connectionID = UUID()
        try await client.refresh()
        fake.pauseNext = true
        let refresh = Task { try await client.refresh() }
        while fake.pause == nil { await Task.yield() }
        fake.connectionID = nil
        fake.pause?.resume()
        fake.pause = nil
        do { try await refresh.value; fatalError("Disconnected refresh succeeded") } catch is CancellationError {}
        expect(client.channel == nil && !client.isConnected, "Disconnect clears prior channel")
        fake.connectionID = UUID()
        try await client.refresh()
        fake.connectionID = nil
        await rejects(.unavailable) { try await client.refresh() }
        expect(client.channel == nil, "Already disconnected refresh clears prior channel")
        fake.connectionID = UUID()
        fake.packets = []
        fake.pauseAddress = KatanaSysEx.export
        let load = Task { try await client.loadTone(tone(), to: .a1) }
        while fake.pause == nil { await Task.yield() }
        load.cancel()
        fake.pause?.resume()
        fake.pause = nil
        do { try await load.value; fatalError("Cancelled load succeeded") } catch is CancellationError {}
        expect(fake.memory[KatanaSysEx.previewMute] == [0], "Cancellation unmutes on the same connection")
        fake.pauseAddress = KatanaSysEx.previewMute
        let stopped = Task { try await client.loadTone(tone(), to: .a1) }
        while fake.pause == nil { await Task.yield() }
        client.stop()
        fake.pause?.resume()
        fake.pause = nil
        do { try await stopped.value; fatalError("Stopped load succeeded") } catch is CancellationError {}
        expect(fake.memory[KatanaSysEx.previewMute] == [0], "Stop after mute still unmutes")
        expect(FileManager.default.fileExists(atPath: "notchcast/docs/katana.md"), "Katana docs live in fork docs")
        let module = KatanaModule(midi: SilentKatanaMIDI())
        module.start()
        expect(!module.client.isConnected && module.audio.isEnabled, "Module starts without opening hardware")
        module.stop()
        expect(!module.client.isEnabled && !module.audio.isEnabled, "Module stops both engines")
        let entries = KatanaModule.register(AppCore())
        expect(entries.count == 1 && entries[0].requires == [.katana] && entries[0].requiresAny.isEmpty,
               "Katana registers one entry behind its switch")
        expect(entries[0].module === KatanaModule.shared, "The registered entry is the shared module")
    }

    @MainActor
    static func audio() async throws {
        let fake = FakeKatanaAudio()
        let audio = KatanaAudioService(transport: fake)
        audio.start()
        fake.isUSB = false
        await rejects(.usbRequired) { try await audio.tune() }
        fake.isUSB = true
        try await audio.tune()
        expect(audio.reading?.note == "A" && audio.reading?.octave == 2, "Dry input tuner")
        audio.stopTuning()
        let root = URL(filePath: "/tmp/katana-test-unused")
        let destination = try KatanaRecording.Destination(wet: root.appending(path: "wet.m4a"),
                                                          dry: root.appending(path: "dry.m4a"))
        try await audio.startRecording(destination)
        await rejects(.busy) { try await audio.tune() }
        expect(audio.activity == .recording, "Busy tuner leaves recording running")
        expect(fake.destination?.wetInputs == [0, 1] && fake.destination?.dryInput == 2, "Wet stereo and dry input 3")
        expect(destination.wetCodec == .aac && destination.wetBitRate == 256_000
               && destination.dryCodec == .appleLossless, "Recording codecs")
        let take = try await audio.finishRecording()
        expect(take.duration == 2 && audio.activity == .idle, "Recording completion")
        try await audio.startRecording(destination)
        fake.connectionID = nil
        await rejects(.unavailable) { _ = try await audio.finishRecording() }
        expect(audio.activity == .idle && audio.lastRecording == nil, "Lost USB connection tears down recording")
        audio.stop()
        expect(fake.stops > 0 && audio.reading == nil, "Stop tears down audio")
    }

    @MainActor
    static func repository() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-katana-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appending(path: "tones.json")
        let data = try JSONEncoder().encode([tone()])
        try data.write(to: library)
        let store = KatanaToneStore(file: library)
        try await store.refresh()
        expect(store.tones.count == 1, "Load private tone library")
        let bad = root.appending(path: "bad.kat3")
        try Data([0]).write(to: bad)
        do { try await store.importFiles([bad]); fatalError("Bad import accepted") } catch {}
        expect(try Data(contentsOf: library) == data, "Failed import preserves library")
    }
}

@MainActor final class AppCore {}

@MainActor
final class SilentKatanaMIDI: KatanaMIDILayer {
    var endpoints: [String] = []
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    func start() throws {}
    func connect(_ name: String) throws { fatalError("No hardware in tests") }
    func send(_ bytes: [UInt8]) throws { fatalError("No hardware in tests") }
    func stop() {}
}
