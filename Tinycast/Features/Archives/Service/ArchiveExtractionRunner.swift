import Foundation

nonisolated struct ArchiveExtractionRunner: Sendable {
    struct Progress: Sendable {
        var bytesWritten: Int64 = 0
        var totalBytes: Int64
    }

    var locator: any ArchiveToolLocating = ArchiveToolLocator()

    @concurrent func extract(
        _ archive: URL, progress: @escaping @MainActor @Sendable (Progress) -> Void = { _ in }
    ) async throws -> URL {
        guard ArchiveFormat.accepts(archive), archive.isFileURL else { throw ArchiveFailure.unsupportedFormat }
        guard let tool = locator.locate() else { throw ArchiveFailure.toolMissing }
        let manager = FileManager.default
        let parent = archive.deletingLastPathComponent()
        for suffix in [".hatchzip", ".hatchzip-tail", ".tmp"]
        where ArchiveFiles.exists(URL(fileURLWithPath: archive.path + suffix)) {
            throw ArchiveFailure.existingProgress
        }
        let listingResult = try await ArchiveProcess.run(tool: tool, arguments: ["list", archive.path], captureListing: true)
        try ArchiveProcess.validate(listingResult.status)
        guard let listing = listingResult.listing, let total = listing.totalBytes else { throw ArchiveFailure.invalidListing }
        try ArchiveRules.validate(listing, archiveBytes: ArchiveFiles.attributes(archive).st_size)
        let check = try await ArchiveProcess.run(
            tool: tool, arguments: ["check", "--keep-archive", "--keep-free", "2GB", "-o", parent.path, archive.path])
        try ArchiveProcess.validate(check.status)
        let warning = try ArchiveFiles.quarantine(archive)
        let staging = parent.appending(path: ".notchcast-extract-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            await progress(Progress(totalBytes: total))
            let extraction = try await ArchiveProcess.run(
                tool: tool, arguments: ["extract", "--keep-archive", "-q", "-o", staging.path, archive.path]
            ) {
                if let written = try? ArchiveFiles.bytes(staging) {
                    await progress(Progress(bytesWritten: written, totalBytes: total))
                }
            }
            try ArchiveProcess.validate(extraction.status)
            try Task.checkCancellation()
            let root = try ArchiveFiles.prepare(staging, quarantine: warning)
            let output = try ArchiveFiles.publish(root, staging: staging, archive: archive)
            try ArchiveFiles.removeStaging(staging)
            return output
        } catch {
            try cleanupKeepProgress(archive, staging: staging)
            try ArchiveFiles.removeStaging(staging)
            throw error
        }
    }

    private func cleanupKeepProgress(_ archive: URL, staging: URL) throws {
        let journal = URL(fileURLWithPath: archive.path + ".hatchzip")
        guard ArchiveFiles.exists(journal) else { return }
        let data = try Data(contentsOf: journal)
        guard let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              saved["keep"] as? Bool == true, saved["output"] as? String == staging.path else {
            throw ArchiveFailure.existingProgress
        }
        for suffix in [".hatchzip", ".hatchzip-tail", ".tmp"] {
            let sidecar = URL(fileURLWithPath: archive.path + suffix)
            if ArchiveFiles.exists(sidecar) { try FileManager.default.removeItem(at: sidecar) }
        }
    }
}
