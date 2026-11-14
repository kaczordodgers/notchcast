import Foundation

extension LowDiskModule {
    static func postNotice(_ space: LowDiskEngine.Space, isLow: Bool = true) {
        let free = ByteCountFormatter.string(fromByteCount: space.free, countStyle: .file)
        let text = isLow ? String(localized: "Low disk space: \(free)", table: "Notchcast")
            : String(localized: "Free disk space: \(free)", table: "Notchcast")
        IslandHUDRouter.post(text, tone: isLow ? .danger : .neutral, id: "lowDisk", symbol: "internaldrive", dwell: 5)
    }

    static func postFailure() {
        IslandHUDRouter.post(String(localized: "Could not read disk space.", table: "Notchcast"),
                             tone: .danger, id: "lowDisk", symbol: "internaldrive", dwell: 5)
    }
}
