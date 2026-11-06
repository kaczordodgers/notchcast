import Darwin
import Foundation

nonisolated enum ArchiveFallbackSpace {
    static func check(_ directory: URL, additionalBytes: Int64) throws {
        var information = statfs()
        guard statfs(directory.path, &information) == 0 else { throw ArchiveFailure.filesystem("statfs") }
        let available = UInt64(information.f_bavail).multipliedReportingOverflow(by: UInt64(information.f_bsize))
        guard !available.overflow, available.partialValue >= 2_000_000_000,
              UInt64(additionalBytes) <= available.partialValue - 2_000_000_000 else {
            throw ArchiveFailure.insufficientSpace
        }
    }
}
