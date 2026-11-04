// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/MachLink/Service/MachLinkManager+Peers.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Service/RemoteFan*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl+Completion.swift
import Foundation

@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }
@MainActor final class FanControl {
    enum Mode { case auto, medium, max }
    var mode = Mode.auto
    var unavailable = false
    var failure: Error?
    var pending: Mode?
    func set(_ mode: Mode) { pending = mode }
    func waitUntilIdle() async {
        await Task.yield()
        if failure == nil, let pending { mode = pending }
    }
}
@MainActor final class MachLinkManager {
    var fanHandler: ((RemoteFanRequest) async throws -> RemoteFanReport)?
    var fanEnabled: () -> Bool = { true }
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
        let peer = MachLinkManager()
        var calls = 0
        let fans = FanControl()
        peer.fanHandler = { request in
            precondition(request == .max)
            calls += 1
            let applied = try await fans.applyAndWait(.max)
            precondition(applied == .max)
            return .init(mode: .max, fans: [.init(actual: 4000, target: 6000, minimum: 1000, maximum: 6000)])
        }
        let module = RemoteFanModule(transport: Channel(peer: peer))
        module.start()
        let report = try await module.run(.max)
        precondition(report.mode == .max && calls == 1)
        peer.fanEnabled = { false }
        do { _ = try await module.run(.max); fatalError("Fan off accepted") }
        catch RemoteFanReport.Failure.unavailable {}
        precondition(calls == 1)
        peer.fanEnabled = { true }
        fans.failure = RemoteFanReport.Failure.busy
        do { _ = try await module.run(.max); fatalError("Fan failure accepted") }
        catch RemoteFanReport.Failure.busy {}
        print("PASS request, peer handler, fan fake, report, disabled refusal")
    }
}
