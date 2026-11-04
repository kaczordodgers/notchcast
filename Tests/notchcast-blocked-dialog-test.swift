// notchcast-sources: Tinycast/Features/RemoteDialog/Service/RemoteDialogModule.swift
// notchcast-sources: Tinycast/Features/RemoteDialog/Service/RemoteDialogWindows.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastCore+RemoteNotice.swift
import Foundation
import CoreGraphics

@MainActor enum NotchcastCore {}
@MainActor final class IslandActivityCenter {
    static let shared = IslandActivityCenter()
    enum Tone { case neutral }
    func showMessage(_ text: String, tone: Tone, dwell: Double) {}
}
enum Theme { enum Duration { static let messageHUD = 1.0 } }

@main @MainActor
struct BlockedDialogTest {
    static func settle() async { for _ in 0..<50 { await Task.yield() } }

    static func main() async throws {
        let suite = "dialog-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.remoteDialogAlert))
        precondition(!NotchcastFeature.remoteDialogAlert.needsIsland)
        var info: [[String: Any]] = []
        var reads = 0
        var notices: [RemoteDialogModule.Notice] = []
        var posted: [String] = []
        let receiver = RemoteDialogModule(windows: { [] }, macName: { "Receiver" }, send: { _ in }) {
            NotchcastCore.deliverRemoteNotice($0, preferences: preferences) { posted.append($0) }
        }
        receiver.start()
        defer { receiver.stop() }
        let sender = RemoteDialogModule(windows: {
            reads += 1
            return RemoteDialogWindows.visible(info)
        }, macName: { "Test Mac" }, send: { notice in
            notices.append(notice)
            let request = try MachLinkMessage(method: "dialog-shown", value: notice)
            let reply = try receiver.response(to: MachLinkMessage.decode(request.encoded()))
            let accepted = try reply.value(as: Bool.self)
            precondition(accepted)
        }, post: { _ in })
        let controller = NotchcastModuleController([
            .init(requires: [.machLink, .remoteDialogAlert], module: sender)
        ], preferences: preferences)
        controller.run()
        await sender.poll()
        precondition(reads == 0)
        preferences.set(.remoteDialogAlert, true)
        await settle()
        precondition(reads == 0)
        preferences.set(.machLink, true)
        await settle()
        func window(_ owner: String, _ id: Int, layer: Int = 1) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: 42,
             kCGWindowNumber as String: id, kCGWindowLayer as String: layer]
        }
        let owners = ["UserNotificationCenter", "CoreServicesUIAgent", "SecurityAgent", "universalAccessAuthWarn"]
        info = owners.enumerated().map { window($0.element, $0.offset) }
        info += [window("Ordinary App", 20), window("SecurityAgent", 21, layer: 0)]
        await sender.poll()
        precondition(notices.count == 4 && posted.count == 4)
        precondition(posted.allSatisfy { $0 == "Test Mac is waiting on a system dialog" })
        await sender.poll()
        receiver.receive(notices[0])
        precondition(notices.count == 4 && posted.count == 4)
        info = []
        await sender.poll()
        preferences.set(.islandStatusMessages, false)
        info = [window("SecurityAgent", 0)]
        await sender.poll()
        precondition(notices.count == 5 && posted.count == 4)
        preferences.set(.remoteDialogAlert, false)
        await settle()
        let count = reads
        await sender.poll()
        precondition(reads == count && !sender.isRunning)
        print("PASS fake windows, transport, routing, de-duplication, switches and status gating")
    }
}
