import Foundation
import Synchronization

final class TestAudioHardware: SystemAudioHardware {
    struct Storage {
        var device: UInt32 = 1
        var volume = 0.5
        var muted: Bool? = false
        var micMuted = false
        var quantum: Double?
        var ignoreVolume = false
        var ignoreMute = false
        var switchOnWrite = false
        var writes: [Double] = []
        var delayedReadBack = false
        var pendingVolume: Double?
        var staleReads = 0
    }
    let storage = Mutex(Storage())

    func output() -> SystemAudioState.Output? {
        storage.withLock {
            if $0.staleReads > 0 {
                $0.staleReads -= 1
            } else if let pending = $0.pendingVolume {
                $0.volume = pending
                $0.pendingVolume = nil
            }
            return .init(device: $0.device, volume: $0.volume, muted: $0.muted)
        }
    }

    func microphone() -> SystemAudioState.Microphone? {
        storage.withLock { .init(device: 9, muted: $0.micMuted) }
    }

    func writeVolume(_ volume: Double, device: UInt32) -> Bool {
        storage.withLock {
            guard $0.device == device else { return false }
            $0.writes.append(volume)
            if $0.delayedReadBack {
                $0.pendingVolume = volume
                $0.staleReads = 20
                return true
            }
            if $0.switchOnWrite { $0.device = 2; return true }
            if !$0.ignoreVolume {
                $0.volume = $0.quantum.map { quantum in (volume / quantum).rounded(.down) * quantum } ?? volume
            }
            return true
        }
    }

    func writeMute(_ muted: Bool, device: UInt32) -> Bool {
        storage.withLock {
            guard $0.device == device, $0.muted != nil else { return false }
            if !$0.ignoreMute { $0.muted = muted }
            return true
        }
    }
}

@main
struct SystemLevelsTests {
    @MainActor static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { fatalError(message) }
        }
        check(LevelNotice(kind: .volume, level: .nan).percent == nil, "Invalid scalar is not a percentage")
        check(LevelNotice(kind: .volume, level: 1.2).percent == 100, "Notice clamps percent")
        check(LevelNotice(kind: .volume, level: 0.5, muted: true).symbol == "speaker.slash.fill", "Muted volume glyph")
        check(LevelNotice(kind: .microphone, level: nil, muted: true).symbol == "mic.slash.fill", "Mic glyph")
        check(VolumeStepPolicy.candidates(from: .nan, increasing: true, fine: false).isEmpty, "Invalid level has no steps")
        check(VolumeStepPolicy.candidates(from: 0.5, increasing: true, fine: true).first == 33.0 / 64, "Fine first step")
        check(VolumeStepPolicy.candidates(from: 0.51, increasing: false, fine: false).first == 7.0 / 16, "Step uses grid")
        let hardware = TestAudioHardware()
        let service = SystemLevelsService(hardware: hardware, observeHardware: false)
        service.start()
        await service.settled()
        var changes: [LevelNotice] = []
        service.onLevelChange = { changes.append($0) }
        hardware.storage.withLock { $0.volume = 0.75; $0.micMuted = true }
        service.refresh()
        await service.settled()
        check(changes.map(\.kind) == [.volume, .microphone], "Changes from any source publish notices")
        service.refresh()
        await service.settled()
        check(changes.count == 2, "Unchanged mixer readings stay quiet")
        hardware.storage.withLock { $0.device = 2; $0.volume = 0.25 }
        service.refresh()
        await service.settled()
        check(changes.count == 2, "Device replacement establishes a baseline")
        hardware.storage.withLock { $0.device = 1; $0.volume = 0.5; $0.quantum = 0.125; $0.writes = [] }
        let coarse = await service.apply(.step(increasing: true, fine: true))
        check(coarse == .fallbackToNativeKeys, "Coarse USB beyond bounded fine retries falls back")
        check(hardware.storage.withLock { $0.writes.count } == 4, "Fine retries are bounded")
        hardware.storage.withLock { $0.volume = 0.5; $0.quantum = nil; $0.delayedReadBack = true; $0.writes = [] }
        check(await service.apply(.step(increasing: true)) == .fallbackToNativeKeys, "Delayed read-back falls back")
        check(hardware.storage.withLock { ($0.writes.max() ?? 0) <= 0.625 },
              "Delayed read-back never writes beyond target plus one step")
        for _ in 0..<21 { _ = hardware.output() }
        check(hardware.storage.withLock { $0.volume } == 0.625, "Delayed device eventually applies the bounded write")
        hardware.storage.withLock {
            $0.delayedReadBack = false; $0.ignoreVolume = true; $0.volume = 0.5
        }
        let active = Task { await service.apply(.step(increasing: true)) }
        while hardware.storage.withLock({ $0.writes.count < 3 }) { await Task.yield() }
        let pending = Task { await service.apply(.step(increasing: true)) }
        await Task.yield()
        let latest = Task { await service.apply(.step(increasing: true)) }
        _ = await (active.value, pending.value, latest.value)
        check(hardware.storage.withLock { $0.writes.count } == 6, "Held steps leave at most one pending write operation")
        hardware.storage.withLock { $0.volume = 0.9375; $0.ignoreVolume = true; $0.quantum = nil }
        check(await service.apply(.step(increasing: true)) == .fallbackToNativeKeys, "Ignoring driver falls back")
        hardware.storage.withLock { $0.ignoreVolume = false; $0.volume = 1 }
        check(await service.apply(.step(increasing: true)) == .applied(.init(kind: .volume, level: 1, muted: false)),
              "Maximum is handled without a write")
        hardware.storage.withLock { $0.volume = 0.5; $0.muted = true }
        check(await service.apply(.step(increasing: true)) == .applied(.init(kind: .volume, level: 0.5625, muted: false)),
              "Volume up unmutes with verification")
        hardware.storage.withLock { $0.volume = 0.5; $0.muted = true }
        check(await service.apply(.step(increasing: false)) == .applied(.init(kind: .volume, level: 0.4375, muted: true)),
              "Volume down preserves mute")
        check(await service.apply(.toggleMute) == .applied(.init(kind: .volume, level: 0.4375, muted: false)),
              "Mute toggle reads back")
        hardware.storage.withLock { $0.ignoreMute = true }
        check(await service.apply(.setMuted(true)) == .fallbackToNativeKeys, "Unconfirmed mute falls back")
        check(await service.apply(.setVolume(.nan)) == .fallbackToNativeKeys, "Invalid direct value rejected")
        hardware.storage.withLock { $0.volume = 0.5; $0.switchOnWrite = true }
        check(await service.apply(.step(increasing: true)) == .cancelled, "Device switch cancels in-flight adjustment")
        hardware.storage.withLock { $0.switchOnWrite = false; $0.volume = 0.5; $0.ignoreMute = false; $0.writes = [] }
        let first = Task { await service.apply(.step(increasing: true)) }
        while hardware.storage.withLock({ $0.writes.isEmpty }) { await Task.yield() }
        let second = Task { await service.apply(.step(increasing: true)) }
        _ = await (first.value, second.value)
        check(hardware.storage.withLock { $0.volume } == 0.625, "Concurrent callers serialize read-modify-write")
        hardware.storage.withLock { $0.ignoreVolume = true; $0.volume = 0.5; $0.writes = [] }
        let cancelled = Task { await service.apply(.step(increasing: true, fine: true)) }
        while hardware.storage.withLock({ $0.writes.isEmpty }) { await Task.yield() }
        cancelled.cancel()
        check(await cancelled.value == .cancelled, "Caller cancellation stops coarse retries")
        service.stop()
        check(!service.isRunning && service.state.output == nil, "Stop clears observations")
        print("PASS: \(checks) audio checks with fake hardware; no real audio writes")
    }
}
