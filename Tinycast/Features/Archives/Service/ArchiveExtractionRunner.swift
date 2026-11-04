import Darwin
import Foundation

nonisolated struct ArchiveExtractionRunner: Sendable {
    struct Progress: Sendable {
        var bytesWritten: Int64 = 0
        var recovery: ArchiveJob.Recovery
        var mode: ArchiveJob.Mode
        var fallback: ArchiveJob.Fallback?
    }

    var locator: any ArchiveToolLocating = ArchiveToolLocator()

    @concurrent func extract(
        _ archive: URL, mode: ArchiveJob.Mode = .keepArchive, recovery: ArchiveJob.Recovery? = nil,
        progress: @escaping @MainActor @Sendable (Progress) -> Void = { _ in }
    ) async throws -> URL {
        guard ArchiveFormat.accepts(archive), archive.isFileURL else { throw ArchiveFailure.unsupportedFormat }
        guard let tool = locator.locate() else { throw ArchiveFailure.toolMissing }
        if mode == .inPlace, let recovery, recovery.readyToPublish {
            try ArchiveJournal.validateStaging(recovery.staging, archive: archive)
            return try await finishInPlace(recovery, archive: archive)
        }
        let plan = try await plan(archive, tool: tool, requested: mode, previous: recovery)
        var update = Progress(recovery: plan.recovery, mode: plan.mode, fallback: plan.fallback)
        let staging = plan.recovery.staging
        do {
            await progress(update)
            let flags = plan.mode == .inPlace ? ["-y", "-q", "--keep-free", "2GB"] : ["--keep-archive", "-q"]
            let initial = update
            let extraction = try await ArchiveProcess.run(
                tool: tool, arguments: ["extract"] + flags + ["-o", staging.path, archive.path]
            ) {
                if let written = try? ArchiveFiles.bytes(staging) {
                    var current = initial
                    current.bytesWritten = written
                    await progress(current)
                }
            }
            try ArchiveProcess.validate(extraction.status)
            if plan.mode == .inPlace {
                update.recovery.readyToPublish = true
                await progress(update)
                return try await finishInPlace(update.recovery, archive: archive)
            }
            try Task.checkCancellation()
            return try finish(plan.recovery, archive: archive)
        } catch {
            if plan.mode == .keepArchive {
                try cleanupKeepProgress(archive, staging: staging)
                try ArchiveFiles.removeStaging(staging)
            } else if !ArchiveFiles.exists(URL(fileURLWithPath: archive.path + ".hatchzip")),
                      ArchiveFiles.exists(archive), (try? ArchiveFiles.bytes(staging)) == 0 {
                try ArchiveFiles.removeStaging(staging)
            }
            throw error
        }
    }

    private struct Plan {
        let recovery: ArchiveJob.Recovery
        let mode: ArchiveJob.Mode
        let fallback: ArchiveJob.Fallback?
    }

    private func plan(
        _ archive: URL, tool: URL, requested: ArchiveJob.Mode, previous: ArchiveJob.Recovery?
    ) async throws -> Plan {
        let manager = FileManager.default
        let parent = archive.deletingLastPathComponent()
        if let journal = try ArchiveJournal.read(archive) {
            if journal.mode == .keepArchive, ArchiveFiles.exists(archive) {
                try cleanupKeepProgress(archive, staging: journal.recovery.staging)
                try ArchiveFiles.removeStaging(journal.recovery.staging)
                return try await plan(archive, tool: tool, requested: requested, previous: nil)
            }
            guard requested == .inPlace else { throw ArchiveFailure.existingProgress }
            var recovery = journal.recovery
            if let previous, previous.staging.path == recovery.staging.path { recovery = previous }
            return Plan(recovery: recovery, mode: journal.mode,
                        fallback: journal.mode == .keepArchive ? .resumingKeepArchive : nil)
        }
        for suffix in [".hatchzip-tail", ".tmp"]
        where ArchiveFiles.exists(URL(fileURLWithPath: archive.path + suffix)) {
            throw ArchiveFailure.existingProgress
        }
        guard try ArchiveFiles.attributes(archive).st_mode & S_IFMT == S_IFREG else {
            throw ArchiveFailure.unsafePath(archive.lastPathComponent)
        }
        let listingResult = try await ArchiveProcess.run(tool: tool, arguments: ["list", archive.path], captureListing: true)
        if listingResult.status == 1 { throw ArchiveFailure.unsafePath(archive.lastPathComponent) }
        try ArchiveProcess.validate(listingResult.status)
        guard let listing = listingResult.listing, let total = listing.totalBytes else { throw ArchiveFailure.invalidListing }
        try ArchiveRules.validate(listing, archiveBytes: ArchiveFiles.attributes(archive).st_size)
        var effective = requested
        var fallback: ArchiveJob.Fallback?
        if requested == .inPlace,
           listing.entries.isEmpty || listing.entries.contains(where: \.isSymlink)
            || !ArchiveFiles.supportsExclusiveRename(parent) {
            effective = .keepArchive
            fallback = .inPlaceCheckRefused(1)
        }
        if effective == .inPlace {
            let check = try await ArchiveProcess.run(
                tool: tool, arguments: ["check", "--keep-free", "2GB", "-o", parent.path, archive.path])
            if check.status != 0 {
                effective = .keepArchive
                fallback = .inPlaceCheckRefused(check.status)
            }
        }
        if effective == .keepArchive {
            let check = try await ArchiveProcess.run(
                tool: tool, arguments: ["check", "--keep-archive", "--keep-free", "2GB", "-o", parent.path, archive.path])
            try ArchiveProcess.validate(check.status)
        }
        try Task.checkCancellation()
        let warning = try ArchiveFiles.quarantine(archive)
        let staging = parent.appending(path: ".notchcast-extract-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do { try ArchiveFiles.applyQuarantine(warning, to: staging) } catch {
            try ArchiveFiles.removeStaging(staging)
            throw error
        }
        return Plan(recovery: ArchiveJob.Recovery(staging: staging, totalBytes: total, quarantine: warning),
                    mode: effective, fallback: fallback)
    }

    private func finishInPlace(_ recovery: ArchiveJob.Recovery, archive: URL) async throws -> URL {
        // Released archive bytes make publication a critical section even after cancellation.
        try await Task.detached {
            do { return try finish(recovery, archive: archive) } catch {
                let recoveredArchive = archive.deletingLastPathComponent()
                    .appending(path: "\(ArchiveFormat.baseName(archive)) (recovered).zip")
                return try ArchiveFiles.publish(recovery.staging, staging: recovery.staging,
                                                archive: recoveredArchive)
            }
        }.value
    }

    private func finish(_ recovery: ArchiveJob.Recovery, archive: URL) throws -> URL {
        let root = try ArchiveFiles.prepare(recovery.staging, quarantine: recovery.quarantine)
        let output = try ArchiveFiles.publish(root, staging: recovery.staging, archive: archive)
        try ArchiveFiles.removeStaging(recovery.staging)
        return output
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
