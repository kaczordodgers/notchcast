// notchcast-sources: Tinycast/Features/MachBlockedDialog/Model/*.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Service/BlockedDialogModule.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-kit: core
import Foundation

@main
struct BlockedDialogTest {
    @MainActor
    static func main() async throws {
        let suite = "app.notchcast.test.blocked-dialog.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.machBlockedDialogAlert))
        let window = BlockedDialogWindow(owner: "SecurityAgent", processID: 42, windowID: 9,
            layer: 1, width: 300, height: 100)
        let ordinary = BlockedDialogWindow(owner: "Editor", processID: 42, windowID: 10,
            layer: 1, width: 300, height: 100)
        var engine = BlockedDialogEngine()
        let now = Date(timeIntervalSince1970: 1000)
        precondition(engine.evaluate([ordinary], now: now) == nil)
        precondition(engine.evaluate([window], now: now) == window)
        precondition(engine.evaluate([window], now: now.addingTimeInterval(90)) == nil)
        precondition(engine.evaluate([], now: now.addingTimeInterval(91)) == nil)
        precondition(engine.evaluate([window], now: now.addingTimeInterval(92)) == window)
        _ = engine.evaluate([], now: now.addingTimeInterval(93))
        precondition(engine.evaluate([window], now: now.addingTimeInterval(94)) == nil)
        precondition(engine.evaluate([window], now: now.addingTimeInterval(152)) == window)
        var alerts: [String] = []
        let module = BlockedDialogModule(transport: { request in
            try MachLinkMessage(id: request.id, method: request.method, value: [window])
        }, enabled: { true }, now: { now }, present: { alerts.append($0) })
        module.check()
        await module.waitUntilIdle()
        precondition(alerts.isEmpty)
        module.start()
        module.check()
        await module.waitUntilIdle()
        precondition(alerts == ["SecurityAgent"] && !module.failed)
        module.check()
        await module.waitUntilIdle()
        precondition(alerts.count == 1)
        module.stop()
        let stale = BlockedDialogModule(transport: { request in
            await Task.yield()
            return try MachLinkMessage(id: request.id, method: "wrong", value: [window])
        }, enabled: { true }, present: { _ in preconditionFailure("Invalid response") })
        stale.start()
        stale.check()
        await stale.waitUntilIdle()
        precondition(stale.failed)
        stale.stop()
        print("blocked dialog: detection, dedupe, cooldown, lifecycle and fake link passed")
    }
}
