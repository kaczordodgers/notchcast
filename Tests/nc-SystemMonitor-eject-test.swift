// notchcast-sources: Tinycast/Features/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorStore.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorStore+Eject.swift
import Foundation

@MainActor
final class EjectProbe {
    var calls = 0
    var gate: CheckedContinuation<DiskEjectResult, Never>?
    var snapshot = MonitorSnapshot()

    func eject(_ url: URL) async -> DiskEjectResult {
        calls += 1
        return await withCheckedContinuation { gate = $0 }
    }
}

@main
@MainActor
struct DiskEjectTests {
    static func main() async {
        precondition(DiskVolume.canEject(isLocal: true, isInternal: nil,
                                        isRoot: false, isEjectable: true))
        precondition(!DiskVolume.canEject(isLocal: true, isInternal: true,
                                         isRoot: false, isEjectable: true))
        precondition(DiskVolume.canEject(isLocal: true, isInternal: false,
                                        isRoot: false, isEjectable: false))
        precondition(!DiskVolume.canEject(isLocal: false, isInternal: false,
                                         isRoot: false, isEjectable: true))
        precondition(!DiskVolume.canEject(isLocal: true, isInternal: false,
                                         isRoot: true, isEjectable: true))
        let external = URL(filePath: "/Volumes/Fake")
        let probe = EjectProbe()
        let store = MonitorStore(sample: {
            MonitorSnapshot(volumes: [
                DiskVolume(name: "Fake", mountPath: external.path, total: 100,
                           available: 50, isEjectable: true),
                DiskVolume(name: "Other", mountPath: "/Volumes/Other", total: 100,
                           available: 50, isEjectable: true),
                DiskVolume(name: "Root", mountPath: "/", total: 100, available: 50)
            ])
        })
        let fake: @Sendable (URL) async -> DiskEjectResult = { await probe.eject($0) }
        let disabled = await store.ejectVolume(at: external, using: fake)
        precondition(awaitResultIsNil(disabled))
        store.acquire()
        store.start()
        while store.latest.volumes.isEmpty { await Task.yield() }
        let protected = await store.ejectVolume(at: URL(filePath: "/"), using: fake)
        guard case .notEjectable = protected else { fatalError("internal volume") }
        let missing = await store.ejectVolume(at: URL(filePath: "/Volumes/Missing"), using: fake)
        guard case .gone = missing else { fatalError("missing volume") }
        let first = Task { await store.ejectVolume(at: external, using: fake) }
        while probe.gate == nil { await Task.yield() }
        guard case .ejecting = store.ejectState(at: external) else { fatalError("pending state") }
        let duplicate = await store.ejectVolume(at: external, using: fake)
        precondition(awaitResultIsNil(duplicate) && probe.calls == 1)
        let independent = await store.ejectVolume(at: URL(filePath: "/Volumes/Other"),
                                                 using: { _ in .gone })
        guard case .gone = independent else { fatalError("independent volume") }
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
        probe.gate?.resume(returning: .busy(error))
        probe.gate = nil
        let failed = await first.value
        guard case .busy(let returned) = failed else { fatalError("busy result") }
        precondition((returned as NSError).code == Int(EBUSY))
        guard case .failed = store.ejectState(at: external) else { fatalError("failed state") }
        let retry = await store.ejectVolume(at: external, using: { _ in .ejected })
        guard case .ejected = retry else { fatalError("retry") }
        guard case .idle = store.ejectState(at: external) else { fatalError("idle state") }
        let closed = Task { await store.ejectVolume(at: external, using: fake) }
        while probe.gate == nil { await Task.yield() }
        store.release()
        probe.gate?.resume(returning: .busy(error))
        probe.gate = nil
        guard case .busy = await closed.value else { fatalError("closed page result") }
        guard case .failed = store.ejectState(at: external) else { fatalError("closed page state") }
        store.acquire()
        let cancelled = Task { await store.ejectVolume(at: external, using: fake) }
        while probe.gate == nil { await Task.yield() }
        cancelled.cancel()
        probe.gate?.resume(returning: .busy(error))
        probe.gate = nil
        let cancelledResult = await cancelled.value
        precondition(awaitResultIsNil(cancelledResult))
        guard case .idle = store.ejectState(at: external) else { fatalError("cancelled state") }
        let pending = Task { await store.ejectVolume(at: external, using: fake) }
        while probe.gate == nil { await Task.yield() }
        store.stop()
        probe.gate?.resume(returning: .ejected)
        let stale = await pending.value
        precondition(awaitResultIsNil(stale))
        guard case .idle = store.ejectState(at: external) else { fatalError("stale state") }
        let sampled = MonitorStore(sample: { await probe.snapshot })
        probe.snapshot = MonitorSnapshot(volumes: [
            DiskVolume(name: "Fake", mountPath: external.path, total: 100,
                       available: 50, isEjectable: true)
        ])
        sampled.acquire()
        sampled.start()
        while sampled.latest.volumes.isEmpty { await Task.yield() }
        _ = await sampled.ejectVolume(at: external, using: { _ in .busy(error) })
        guard case .failed = sampled.ejectState(at: external) else { fatalError("sampled failure") }
        sampled.release()
        probe.snapshot = MonitorSnapshot()
        sampled.acquire()
        while !sampled.latest.volumes.isEmpty { await Task.yield() }
        guard case .idle = sampled.ejectState(at: external) else { fatalError("removed volume state") }
        sampled.stop()
        print("Disk eject checks passed (injected ejectors only)")
    }

    static func awaitResultIsNil(_ result: DiskEjectResult?) -> Bool { result == nil }
}
