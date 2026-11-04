import Foundation

extension LowDiskModule {
    static func postNotice(_ space: LowDiskEngine.Space) {
        let free = ByteCountFormatter.string(fromByteCount: space.free, countStyle: .file)
        IslandActivityCenter.shared.showMessage(String(localized: "Low disk space: \(free)"),
                                               tone: .danger, dwell: 5)
    }
}
