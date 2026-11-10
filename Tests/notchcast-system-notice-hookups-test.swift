// notchcast-kit: host
// notchcast-sources: Tinycast/Features/LowDisk/Model/LowDiskEngine.swift
// notchcast-sources: Tinycast/Features/LowDisk/LowDiskModule.swift
// notchcast-sources: Tinycast/Features/LowDisk/LowDiskModule+Notice.swift
// notchcast-sources: Tinycast/Features/SystemNotices/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemNotices/SystemNoticesModule.swift
// notchcast-sources: Tinycast/Features/SystemNotices/SystemNoticesModule+Notice.swift
import Foundation

@MainActor protocol NotchcastModule {}
enum DialogTone {}
@MainActor final class LowDiskManager {
    var onNotice: ((LowDiskEngine.Space) -> Void)?
    func start() {}
    func stop() {}
}
@MainActor final class SystemNoticesManager {
    var onNotice: ((SystemNoticeEngine.Notice) -> Void)?
    func start() {}
    func stop() {}
}
@MainActor enum IslandHUDRouter {
    enum Tone { case danger, neutral }
    static var messages: [String] = []
    static var ids: [String?] = []
    @discardableResult
    static func post(_ text: String, tone: Tone = .neutral, id: String? = nil, symbol: String? = nil,
                     dwell: TimeInterval = 0) -> UUID? {
        messages.append(text)
        ids.append(id)
        return nil
    }
}
@main struct NoticeTests {
    @MainActor static func main() {
        var refreshes = 0
        NotchcastHost.current.refreshNotchcastCommands = { refreshes += 1 }
        let disk = LowDiskModule()
        disk.start()
        precondition(refreshes == 1)
        let space = LowDiskEngine.Space(free: 1_000_000, total: 100_000_000)
        disk.manager.onNotice?(space)
        precondition(disk.latest == space)
        precondition(IslandHUDRouter.messages.last?.hasPrefix("Low disk space:") == true)
        disk.stop()
        precondition(disk.manager.onNotice == nil && refreshes == 2)
        let system = SystemNoticesModule()
        system.start()
        for notice in [SystemNoticeEngine.Notice.wifi(available: false), .wifi(available: true),
                       .tailscale(.connected), .lowBattery(percent: 10, threshold: 10)] {
            system.manager.onNotice?(notice)
            precondition(system.latest == notice)
        }
        precondition(IslandHUDRouter.messages.count == 5)
        precondition(IslandHUDRouter.messages.last == "Low battery: 10%")
        precondition(IslandHUDRouter.ids == ["lowDisk", "system.wifi", "system.wifi",
                                                         "system.tailscale", "system.battery"])
        system.stop()
        precondition(system.manager.onNotice == nil)
        print("Verified low disk and system notice callbacks reach the island router and detach on stop")
    }
}
