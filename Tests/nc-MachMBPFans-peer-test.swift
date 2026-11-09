// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkRequestBudget.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Service/RemoteFan*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl+Completion.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/RemoteFanPeer.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/FanOwnershipJournal.swift
import Foundation
import Synchronization

@MainActor final class MonitorModule {
    let fans = FanControl(runner: { _ in await HelperEdge.apply() })
}
struct RootHelperClient {
    enum Failure: Error { case executionFailed(Int) }
    func run(_ command: RootContract.Command) async throws {}
}
@MainActor enum HelperEdge {
    static var onApply: (() -> Void)?
    static func apply() { onApply?() }
}
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
@MainActor final class MachLinkManager {
    var routes: [String: @MainActor (MachLinkMessage) async throws -> MachLinkMessage] = [:]
    func register(_ method: String, _ route: @escaping @MainActor (MachLinkMessage) async throws -> MachLinkMessage) {
        routes[method] = route
    }
}
@MainActor final class MachLinkChannel {
    let manager = MachLinkManager()
    var calls = 0
    func request<Value: Encodable, Response: Decodable>(_ value: Value, method: String,
                                                        as type: Response.Type) async throws -> Response {
        calls += 1
        guard let route = manager.routes[method] else { throw MachLinkMessage.Failure.disconnected }
        return try await route(MachLinkMessage(method: method, value: value)).value(as: type)
    }
}
@main struct FanPeerTest {
    @MainActor static func main() async throws {
        let applyAndRestore = RootContract.Operation.change.timeout * 2
        precondition(MachLinkRequestBudget.responder == applyAndRestore + .seconds(2))
        precondition(MachLinkRequestBudget.requester == MachLinkRequestBudget.responder + .seconds(2))
        let channel = MachLinkChannel()
        let monitor = MonitorModule()
        let fans = monitor.fans
        monitor.registerRemoteFanRoute(on: channel)
        let module = RemoteFanModule(transport: MachLinkFanTransport(channel: channel))
        module.start()
        let report = try await module.run(.max)
        precondition(report.mode == .max && channel.calls == 1)
        NotchcastPreferences.shared.enabled = false
        do { _ = try await module.run(.max); fatalError("Fan off accepted") } catch RemoteFanReport.Failure.unavailable {}
        precondition(fans.mode.remoteMode == .max)
        NotchcastPreferences.shared.enabled = true
        for (request, expected, target): (RemoteFanRequest, RemoteFanReport.Mode, Double) in [
            (.auto, .auto, 6000), (.cycle, .mid, 4000), (.cycle, .max, 6000), (.cycle, .auto, 6000)
        ] {
            SMCClient.target.withLock { $0 = target }
            let result = try await module.run(request)
            precondition(result.mode == expected)
        }
        HelperEdge.onApply = { NotchcastPreferences.shared.enabled = false }
        do { _ = try await module.run(.max); fatalError("Disabled during apply") } catch RemoteFanReport.Failure.unavailable {}
        HelperEdge.onApply = nil
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
            if scenario == 1 { _ = try await fans.applyAndWait(.auto) }
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
        let failed = FanControl(runner: { _ in throw RemoteFanReport.Failure.busy })
        do {
            _ = try await failed.applyAndWait(.max)
            fatalError("Helper failure accepted")
        } catch RemoteFanReport.Failure.busy {}
        print("PASS shipped RemoteFanPeer and FanControl, mapping, post-await checks, validation, helper failure, budgets")
    }
}
