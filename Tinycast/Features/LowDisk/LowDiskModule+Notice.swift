import Foundation

extension LowDiskModule {
    static func postNotice(_ space: LowDiskEngine.Space) {
        let free = ByteCountFormatter.string(fromByteCount: space.free, countStyle: .file)
        IslandHUDRouter.post(String(localized: "Low disk space: \(free)", table: "Notchcast"),
                             tone: .danger, id: "lowDisk", symbol: "internaldrive", dwell: 5)
    }
}
