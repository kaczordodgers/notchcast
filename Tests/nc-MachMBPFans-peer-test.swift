// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkRequestBudget.swift
// notchcast-sources: Tinycast/Features/MachLink/Service/MachLinkManager+Peers.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Service/RemoteFan*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl+Completion.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/RemoteFanPeer.swift
import Foundation
import Synchronization

@MainActor final class MonitorModule { let fans = FanControl() }
enum NotchcastFeature { case machLink, systemMonitor, fanControl }
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = true
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}
struct SMCClient {
    static let target = Mutex(6000.0)
    static let gate = Mutex<(DispatchSemaphore, DispatchSemaphore)?>(nil)
    static let entered = Mutex(false)
    init?() {}
    func value(_ key: String) -> Double? {
        if key == "FNum", let gate = Self.gate.withLock({ $0 }) {
            gate.0.signal()
            Self.entered.withLock { $0 = true }
            gate.1.wait()
        }
        return switch key {
        case "FNum": 1
        case "F0Ac": 3000
        case "F0Tg": Self.target.withLock { $0 }
        case "F0Mn": 1000
        case "F0Mx": 6000
        default: nil
        }
    }
}

@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }
@MainActor final class FanControl {
    enum Mode { case auto, medium, max }
    var mode = Mode.auto
    var unavailable = false
    var failure: Error?
    var pending: Mode?
    var onWait: (() -> Void)?
    func set(_ mode: Mode) { pending = mode }
    func waitUntilIdle() async {
        await Task.yield()
        if failure == nil, let pending { mode = pending }
        onWait?()
    }
}
@MainActor final class MachLinkManager {
    var fanHandler: ((RemoteFanRequest) async throws -> RemoteFanReport)?
    var fanEnabled: () -> Bool = { true }
    var screenEnabled: () -> Bool = { true }
    var screenAddress: () async throws -> RemoteScreenState.Availability = { throw RemoteScreenRequest.Failure.unavailable }
}
@MainActor struct Channel: RemoteFanTransport {
    let peer: MachLinkManager
    func exchange(_ request: MachLinkMessage) async throws -> MachLinkMessage {
        try await peer.peerResponse(to: request)!
    }
}
@main struct FanPeerTest {
    @MainActor static func main() async throws {
        precondition(MachLinkRequestBudget.requester > MachLinkRequestBudget.responder)
        precondition(MachLinkRequestBudget.responder > .seconds(5))
        let peer = MachLinkManager()
        var calls = 0
        let monitor = MonitorModule()
        let fans = monitor.fans
        peer.fanHandler = { request in
            calls += 1
            return try await monitor.remoteFanReport(request)
        }
        let module = RemoteFanModule(transport: Channel(peer: peer))
        module.start()
        let report = try await module.run(.max)
        precondition(report.mode == .max && calls == 1)
        peer.fanEnabled = { false }
        do { _ = try await module.run(.max); fatalError("Fan off accepted") } catch RemoteFanReport.Failure.unavailable {}
        precondition(calls == 1)
        peer.fanEnabled = { true }
        fans.failure = RemoteFanReport.Failure.busy
        do { _ = try await module.run(.max); fatalError("Fan failure accepted") } catch RemoteFanReport.Failure.busy {}
        fans.failure = nil
        for (request, expected, target): (RemoteFanRequest, RemoteFanReport.Mode, Double) in [
            (.auto, .auto, 6000), (.cycle, .mid, 4000), (.cycle, .max, 6000), (.cycle, .auto, 6000)
        ] {
            SMCClient.target.withLock { $0 = target }
            let result = try await module.run(request)
            precondition(result.mode == expected)
        }
        fans.onWait = { NotchcastPreferences.shared.enabled = false }
        do { _ = try await module.run(.max); fatalError("Disabled during apply") } catch RemoteFanReport.Failure.unavailable {}
        fans.onWait = nil
        NotchcastPreferences.shared.enabled = true
        SMCClient.target.withLock { $0 = 2000 }
        do {
            _ = try await module.run(.max)
            fatalError("Invalid target accepted")
        } catch RemoteFanReport.Failure.invalidReport {}
        SMCClient.target.withLock { $0 = 6000 }
        for scenario in 0..<3 {
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            SMCClient.gate.withLock { $0 = (entered, release) }
            SMCClient.entered.withLock { $0 = false }
            let task = Task { try await monitor.remoteFanReport(.max) }
            while !SMCClient.entered.withLock({ $0 }) { await Task.yield() }
            if scenario == 0 { NotchcastPreferences.shared.enabled = false }
            if scenario == 1 { fans.mode = .auto }
            if scenario == 2 { task.cancel() }
            release.signal()
            do {
                _ = try await task.value
                fatalError("Stale SMC result accepted")
            } catch RemoteFanReport.Failure.unavailable { precondition(scenario == 0)
            } catch RemoteFanReport.Failure.busy { precondition(scenario == 1)
            } catch is CancellationError { precondition(scenario == 2) }
            NotchcastPreferences.shared.enabled = true
            SMCClient.gate.withLock { $0 = nil }
        }
        print("PASS shipped RemoteFanPeer mapping, post-await switch check, report validation, helper failure")
    }
}
