// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift Tinycast/Features/MachLink/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift Tinycast/Platform/KeychainSecretStore.swift
import Foundation
import Network

// A failed listener or browser restarts; a stale or stopped one does not.
@main
@MainActor
struct MachLinkRestartTest {
    static func main() async throws {
        let manager = MachLinkManager()
        defer { manager.stop() }
        try manager.start(pairing: try MachLinkPairing.create(), name: "restart-test-" + UUID().uuidString)
        let first = try objects(of: manager)
        let failure = NWError.posix(.ECONNRESET)
        first.listener.stateUpdateHandler?(.failed(failure))
        let afterListener = try await replacement(in: manager) { $0.listener !== first.listener }
        precondition(afterListener != nil, "failed listener was not restarted")
        precondition(afterListener?.browser !== first.browser && manager.serviceName != nil)
        guard let second = afterListener else { return }
        second.browser.stateUpdateHandler?(.failed(failure))
        let afterBrowser = try await replacement(in: manager) { $0.browser !== second.browser }
        precondition(afterBrowser != nil, "failed browser was not restarted")
        guard let third = afterBrowser else { return }
        first.listener.stateUpdateHandler?(.failed(failure))
        first.browser.stateUpdateHandler?(.failed(failure))
        try await Task.sleep(for: .seconds(3))
        let unchanged = try objects(of: manager)
        precondition(unchanged.listener === third.listener && unchanged.browser === third.browser,
                     "failure of a replaced listener or browser restarted the current ones")
        third.listener.stateUpdateHandler?(.failed(failure))
        manager.stop()
        try await Task.sleep(for: .seconds(3))
        precondition((try? objects(of: manager)) == nil, "failure before stop() restarted a stopped manager")
        print("PASS: failed listener and browser restart; stale and stopped failures do not")
    }

    typealias Objects = (listener: NWListener, browser: NWBrowser)

    static func objects(of manager: MachLinkManager) throws -> Objects {
        var listener: NWListener?
        var browser: NWBrowser?
        for child in Mirror(reflecting: manager).children {
            switch child.label {
            case "listener": listener = Mirror(reflecting: child.value).children.first?.value as? NWListener
            case "browser": browser = Mirror(reflecting: child.value).children.first?.value as? NWBrowser
            default: break
            }
        }
        guard let listener, let browser else { throw CocoaError(.fileNoSuchFile) }
        return (listener, browser)
    }

    static func replacement(in manager: MachLinkManager, where changed: (Objects) -> Bool) async throws -> Objects? {
        for _ in 0..<60 {
            if let now = try? objects(of: manager), changed(now) { return now }
            try await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
