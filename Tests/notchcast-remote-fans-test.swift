// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Service/RemoteFan*.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class FakeFanTransport: RemoteFanTransport {
    var requests: [RemoteFanRequest] = []
    var mode = RemoteFanReport.Mode.auto
    var corrupt = false
    var suspend: (() async -> Void)?

    func exchange(_ request: MachLinkMessage) async throws -> MachLinkMessage {
        let request = try MachLinkMessage.decode(request.encoded())
        let verb = try request.value(as: RemoteFanRequest.self)
        requests.append(verb)
        if let suspend { await suspend() }
        if verb == .cycle { mode = mode.next }
        if let value = RemoteFanReport.Mode(rawValue: verb.rawValue) { mode = value }
        let target: Double = mode == .mid ? 4_400 : 6_000
        let report = RemoteFanReport(mode: mode, fans: [
            .init(actual: 3_000, target: target, minimum: 2_000, maximum: 6_000)
        ])
        return try MachLinkMessage(id: corrupt ? UUID() : request.id, method: request.method, value: report)
    }
}

@main
struct RemoteFanTests {
    @MainActor
    static func main() async throws {
        let transport = FakeFanTransport()
        let module = RemoteFanModule(transport: transport)
        do { _ = try await module.run(.cycle); fatalError("disabled request") } catch RemoteFanReport.Failure.unavailable {}
        module.start()
        for mode: RemoteFanReport.Mode in [.mid, .max, .auto] {
            let value = try await module.run(.cycle)
            precondition(value.mode == mode)
        }
        for verb in RemoteFanRequest.allCases { _ = try await module.run(verb) }
        transport.corrupt = true
        do { _ = try await module.run(.status); fatalError("uncorrelated reply") } catch MachLinkMessage.Failure.invalidMessage {}
        transport.corrupt = false
        for reading in [
            RemoteFanReport.Reading(actual: -1, target: 4_400, minimum: 2_000, maximum: 6_000),
            .init(actual: 0, target: 4_400, minimum: 6_000, maximum: 2_000),
            .init(actual: .infinity, target: 4_400, minimum: 2_000, maximum: 6_000),
            .init(actual: 3_000, target: 4_425, minimum: 2_000, maximum: 6_000)
        ] {
            do {
                try RemoteFanReport(mode: .mid, fans: [reading]).validate(for: .status)
                fatalError("invalid RPM accepted")
            } catch RemoteFanReport.Failure.invalidReport {}
        }
        transport.suspend = { module.stop(); module.start() }
        do { _ = try await module.run(.status); fatalError("stale response") } catch is CancellationError {}
        precondition(module.report == nil)
        print("Remote fans: cycle, parsing, validation, disabled and stale results passed")
    }
}
