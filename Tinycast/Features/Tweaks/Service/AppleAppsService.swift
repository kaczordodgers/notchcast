import Foundation

nonisolated struct AppleAppsService: Sendable {
    enum Failure: Error { case missingInode }

    func musicLabel(app: URL) throws -> String {
        func inode(_ url: URL) throws -> UInt64 {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let number = attributes[.systemFileNumber] as? NSNumber else { throw Failure.missingInode }
            return number.uint64Value
        }
        return try AppleAppsPolicy.musicLabel(bundleInode: inode(app),
                                              executableInode: inode(app.appendingPathComponent("Contents/MacOS/Music")))
    }
}
