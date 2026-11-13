// notchcast-sources: Tinycast/Features/MachBlockedDialog/Model/*.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Service/BlockedDialogModule.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
import Foundation

@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }

@main struct DialogDetectionTest {
    @MainActor static func main() async throws {
        let window = BlockedDialogWindow(owner: "SecurityAgent", processID: 42, windowID: 9,
            layer: 1, width: 300, height: 100)
        var windows = [window]
        var alerts = 0
        let module = BlockedDialogModule(transport: { request in
            try MachLinkMessage(id: request.id, method: request.method, value: windows)
        }, enabled: { true }, now: { Date(timeIntervalSince1970: 1000) }, present: { _ in alerts += 1 })
        module.start()
        for _ in 0..<2 {
            module.check()
            await module.waitUntilIdle()
            precondition(module.detectedOwner == "SecurityAgent" && !module.failed)
        }
        precondition(alerts == 1)
        windows = []
        module.check()
        await module.waitUntilIdle()
        precondition(module.detectedOwner == nil && !module.failed)
        module.stop()
        print("PASS repeated checks retain detected owner while alerts stay deduplicated; cleared dialog disappears")
    }
}
