// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Service/*.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift
// notchcast-kit: root core
import Foundation

@main
struct RemoteScreenTest {
    @MainActor
    static func main() async throws {
        let suite = "app.notchcast.test.remote-screen.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.remoteScreen))
        for host in ["", "user@host", "host/path", "host?password=x", "host#fragment", "host name", "..", ":::"] {
            do {
                _ = try RemoteScreenRequest(host: host).validatedURL()
                fatalError("Invalid host accepted")
            } catch RemoteScreenRequest.Failure.invalidHost {}
        }
        let request = RemoteScreenRequest(host: "peer.local")
        let url = try request.validatedURL()
        precondition(url.absoluteString == "vnc://peer.local")
        var calls = 0
        var opened: [RemoteScreenState.Client] = []
        let coordinator = RemoteScreenCoordinator(transport: { message in
            calls += 1
            precondition(message.method == "remote-screen-availability")
            let enabled = try message.value(as: Bool.self)
            precondition(enabled)
            return try MachLinkMessage(id: message.id, method: message.method,
                value: RemoteScreenState.Availability(screenSharingEnabled: true))
        }, open: { url, client in
            precondition(url.user == nil && url.password == nil)
            opened.append(client)
        })
        do {
            try await coordinator.show(request, preferredClientInstalled: true)
            fatalError("Disabled request accepted")
        } catch RemoteScreenRequest.Failure.unavailable {}
        precondition(calls == 0)
        coordinator.start()
        try await coordinator.show(request, preferredClientInstalled: true)
        precondition(coordinator.state == .opened && !coordinator.usedFallback)
        try await coordinator.show(request, preferredClientInstalled: false)
        precondition(coordinator.usedFallback && opened == [.preferred, .apple])
        coordinator.stop()
        precondition(coordinator.state == .disabled && !coordinator.usedFallback)
        let invalid = RemoteScreenCoordinator(transport: { message in
            try MachLinkMessage(method: message.method,
                value: RemoteScreenState.Availability(screenSharingEnabled: true))
        }, open: { _, _ in fatalError("Invalid response opened client") })
        invalid.start()
        do {
            try await invalid.show(request, preferredClientInstalled: true)
            fatalError("Mismatched response accepted")
        } catch RemoteScreenRequest.Failure.invalidResponse {}
        precondition(invalid.state == .failed)
        var pending: CheckedContinuation<MachLinkMessage, Error>?
        var sent: MachLinkMessage?
        let stale = RemoteScreenCoordinator(transport: { message in
            sent = message
            return try await withCheckedThrowingContinuation { pending = $0 }
        }, open: { _, _ in fatalError("Stopped operation opened client") })
        stale.start()
        let task = Task { try await stale.show(request, preferredClientInstalled: true) }
        while pending == nil { await Task.yield() }
        stale.stop()
        let message = sent!
        pending!.resume(returning: try MachLinkMessage(id: message.id, method: message.method,
            value: RemoteScreenState.Availability(screenSharingEnabled: true)))
        do {
            try await task.value
            fatalError("Stale response accepted")
        } catch is CancellationError {}
        precondition(stale.state == .disabled)
        print("PASS validation, disabled gate, message correlation, client selection, teardown")
    }
}
