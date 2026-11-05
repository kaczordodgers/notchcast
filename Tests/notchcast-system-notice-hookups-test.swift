// notchcast-sources: Tinycast/Features/LowDisk/Model/LowDiskEngine.swift
// notchcast-sources: Tinycast/Features/LowDisk/LowDiskModule.swift
// notchcast-sources: Tinycast/Features/LowDisk/LowDiskModule+Notice.swift
// notchcast-sources: Tinycast/Features/SystemNotices/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemNotices/SystemNoticesModule.swift
// notchcast-sources: Tinycast/Features/SystemNotices/SystemNoticesModule+Notice.swift
import Foundation

@MainActor protocol NotchcastModule {}
@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = Index()
    final class Index { func refreshNotchcastCommands() {} }
}
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
@MainActor final class IslandActivityCenter {
    enum Tone { case danger, neutral }
    static let shared = IslandActivityCenter()
    var messages: [String] = []
    var ids: [String?] = []
    func showMessage(_ text: String, tone: Tone, dwell: TimeInterval, id: String?) {
        messages.append(text)
        ids.append(id)
    }
}
@main struct NoticeTests {
    @MainActor static func main() {
        let disk = LowDiskModule()
        disk.start()
        let space = LowDiskEngine.Space(free: 1_000_000, total: 100_000_000)
        disk.manager.onNotice?(space)
        precondition(disk.latest == space)
        precondition(IslandActivityCenter.shared.messages.last?.hasPrefix("Low disk space:") == true)
        disk.stop()
        precondition(disk.manager.onNotice == nil)
        let system = SystemNoticesModule()
        system.start()
        for notice in [SystemNoticeEngine.Notice.wifi(available: false), .wifi(available: true),
                       .tailscale(.connected), .lowBattery(percent: 10, threshold: 10)] {
            system.manager.onNotice?(notice)
            precondition(system.latest == notice)
        }
        precondition(IslandActivityCenter.shared.messages.count == 5)
        precondition(IslandActivityCenter.shared.messages.last == "Low battery: 10%")
        precondition(IslandActivityCenter.shared.ids == ["lowDisk", "system.wifi", "system.wifi",
                                                         "system.tailscale", "system.battery"])
        system.stop()
        precondition(system.manager.onNotice == nil)
        print("Verified low disk and system notice callbacks reach island messages and detach on stop")
    }
}
