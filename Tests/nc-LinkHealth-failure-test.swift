// notchcast-sources: Tinycast/Features/LinkHealth/Model/*.swift
// notchcast-sources: Tinycast/Features/LinkHealth/Service/*.swift
// notchcast-sources: Tinycast/Features/LinkHealth/LinkHealthModule.swift
import Foundation

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

enum MachLinkMethod: String { case linkHealth }
enum MachLinkMessage {
    enum Failure: Error { case disconnected }
}

@MainActor final class MachLinkChannel {
    var response = true
    var failure = false
    func request(_ value: Bool, method: String, timeout: Duration, as: Bool.Type) async throws -> Bool {
        precondition(value && method == "linkHealth" && timeout == .seconds(2))
        if failure { throw MachLinkMessage.Failure.disconnected }
        return response
    }
}

@main struct LinkHealthFailureTests {
    @MainActor static func main() async throws {
        let channel = MachLinkChannel()
        let latency = try await channel.probeHealth()
        precondition(latency >= .zero)
        channel.response = false
        do {
            _ = try await channel.probeHealth()
            preconditionFailure("A false response must fail")
        } catch MachLinkMessage.Failure.disconnected {}
        channel.failure = true
        do {
            _ = try await channel.probeHealth()
            preconditionFailure("A transport error must propagate")
        } catch MachLinkMessage.Failure.disconnected {}
        var calls = 0
        var notices: [String] = []
        let module = LinkHealthModule(probe: {
            calls += 1
            channel.failure = calls <= 3
            channel.response = true
            return try await channel.probeHealth()
        }, pause: { await Task.yield() }, post: { notices.append($0) })
        module.start()
        while calls < 6 { await Task.yield() }
        precondition(module.health.reachability == .up)
        precondition(notices == ["Mac link lost.", "Mac link restored."])
        module.stop()
        precondition(module.health.reachability == .unknown && !module.isRunning)
        print("PASS health adapter true/false/throw; polling errors post lost once, recovery once, stop resets")
    }
}
