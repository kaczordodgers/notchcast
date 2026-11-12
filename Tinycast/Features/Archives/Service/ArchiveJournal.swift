import Darwin
import Foundation

nonisolated struct ArchiveJournal {
    let recovery: ArchiveJob.Recovery
    let mode: ArchiveJob.Mode
    let outputPath: String

    static func read(_ archive: URL) throws -> ArchiveJournal? {
        let archive = ArchiveFiles.resolvedParent(archive)
        let journal = URL(fileURLWithPath: archive.path + ".hatchzip")
        guard ArchiveFiles.exists(journal) else { return nil }
        let descriptor = open(journal.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ArchiveFailure.existingProgress }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= 16_000_000, info.st_uid == getuid(),
              let data = try handle.read(upToCount: 16_000_001),
              let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = saved["output"] as? String, let total = saved["total_size"] as? Int64, total >= 0,
              let parts = saved["parts"] as? [[Any]],
              parts.contains(where: {
                  guard let path = $0.first as? String else { return false }
                  return ArchiveFiles.samePath(URL(fileURLWithPath: path), archive)
              }) else {
            throw ArchiveFailure.existingProgress
        }
        let staging = ArchiveFiles.resolvedParent(URL(fileURLWithPath: path))
        try validateStaging(staging, archive: archive)
        for suffix in [".hatchzip-tail", ".tmp"] {
            let sidecar = URL(fileURLWithPath: archive.path + suffix)
            if ArchiveFiles.exists(sidecar) {
                let attributes = try ArchiveFiles.attributes(sidecar)
                guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_uid == getuid() else {
                    throw ArchiveFailure.existingProgress
                }
            }
        }
        let mode: ArchiveJob.Mode = saved["keep"] as? Bool == true ? .keepArchive : .inPlace
        let warning = try ArchiveFiles.quarantine(ArchiveFiles.exists(archive) ? archive : staging)
        return ArchiveJournal(recovery: ArchiveJob.Recovery(staging: staging, totalBytes: total, quarantine: warning),
                              mode: mode, outputPath: path)
    }

    static func validateStaging(_ staging: URL, archive: URL) throws {
        let staging = ArchiveFiles.resolvedParent(staging)
        let archive = ArchiveFiles.resolvedParent(archive)
        let prefix = ArchiveFiles.stagingPrefix
        guard ArchiveFiles.samePath(staging.deletingLastPathComponent(), archive.deletingLastPathComponent()),
              staging.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(staging.lastPathComponent.dropFirst(prefix.count))) != nil else {
            throw ArchiveFailure.existingProgress
        }
        let info = try ArchiveFiles.attributes(staging)
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw ArchiveFailure.existingProgress }
    }
}
