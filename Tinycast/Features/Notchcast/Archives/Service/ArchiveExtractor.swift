import Foundation

/// One archive from listing to its place beside it; every program call goes through `run`.
nonisolated struct ArchiveExtractor: Sendable {
    var locate: @Sendable (String) async -> URL?
    var run: @Sendable (URL, [String], [String: String]) async throws -> ArchiveProcessResult

    /// Asked once when keeping the archive does not fit, with HatchZip's in-place plan.
    typealias AskInPlace = @Sendable (_ plan: String) async -> Bool
    /// The typed password, or nil when the user cancelled.
    typealias AskPassword = @Sendable (_ wrong: Bool) async -> String?

    /// The final file or folder; with no `askPassword` a protected archive fails.
    @concurrent
    func extract(
        _ job: ArchiveJob, askPassword: AskPassword?, askInPlace: AskInPlace,
        onInPlace: @Sendable (Bool) async -> Void,
        resumeStaging: @Sendable (_ reportedPath: String?) async -> URL? = { _ in nil }
    ) async throws -> URL? {
        guard var route = ArchiveRoute(fileName: job.name) else { throw ArchiveFailure.notArchive(job.name) }
        if route.engine == .hatchzip, job.name.lowercased().hasSuffix(".zip"), hasLegacyNames(job.archive),
            await locate(ArchiveTool.unar.name) != nil
        {
            route = ArchiveRoute(engine: .unar, stem: route.stem)
        }
        let tools = ArchiveCommandLine.tools(route.engine)
        let extractor = try await find(tools.extract)
        var password: String?
        var asked = 0
        func askForPassword() async throws {
            guard let askPassword, case .ask(let wrong) = ArchivePassword.next(asked: asked) else {
                throw ArchiveFailure.password
            }
            asked += 1
            guard let answer = await askPassword(wrong) else { throw CancellationError() }
            try Task.checkCancellation()
            password = answer
        }
        if let lister = tools.list, let arguments = ArchiveCommandLine.list(route.engine, archive: job.archive) {
            let lister = try await find(lister)
            var listed = try await run(lister, arguments, [:])
            while route.engine == .hatchzip, listed.status == ArchiveFailure.hatchzipPassword {
                try await askForPassword()
                listed = try await run(lister, arguments, ArchivePassword.environment(password, engine: route.engine))
            }
            if let failure = route.engine == .hatchzip ? ArchiveFailure.hatchzip(listed) : .tool(listed) {
                throw failure
            }
            let listing = route.engine == .unar ? try ArchiveListing.lsar(Data(listed.output.utf8))
                : route.engine == .bsdtar ? ArchiveListing.bsdtar(listed.output) : ArchiveListing.hatchzip(listed.output)
            if let refusal = ArchiveSafety.refusal(for: listing, archiveSize: Self.size(job.archive) ?? 0) {
                throw ArchiveFailure.unsafe(refusal)
            }
        }
        var destination = job
        if route.engine == .hatchzip, let staging = await resumeStaging(nil) {
            destination.staging = staging
        }
        let program = route.engine.isSingleStream ? URL(filePath: "/bin/sh") : extractor
        let archiveSize = Self.size(job.archive) ?? 0
        var inPlace = job.inPlace
        var askingAtExtract = false
        var followedReportedPath = false
        let hadStaging = FileManager.default.fileExists(atPath: job.staging.path)
        while true {
            try Task.checkCancellation()
            let resuming = destination.staging != job.staging
            let keepOnly = resuming || (password != nil && !ArchivePassword.allowsInPlace(fileName: job.name))
            if keepOnly, inPlace {
                inPlace = false
                await onInPlace(false)
            }
            let secret = ArchivePassword.environment(password, engine: route.engine)
            // Only HatchZip resumes into what an earlier run left.
            if route.engine != .hatchzip { try? FileManager.default.removeItem(at: destination.staging) }
            try FileManager.default.createDirectory(at: destination.staging, withIntermediateDirectories: true)
            let result = try await run(program, ArchiveCommandLine.extract(
                route.engine, tool: extractor, archive: job.archive, staging: destination.staging, stem: route.stem,
                inPlace: inPlace, outputBlocks: ArchiveSafety.outputBlocks(archiveSize: archiveSize)), secret)
            if route.engine != .hatchzip {
                if let failure = ArchiveFailure.tool(result) { throw failure }
                break
            }
            if result.status == ArchiveFailure.hatchzipPaused { throw CancellationError() }
            guard let failure = ArchiveFailure.hatchzip(result) else { break }
            func removeEmptyScratch() {
                guard !resuming, !hadStaging,
                    (try? FileManager.default.contentsOfDirectory(atPath: job.staging.path))?.isEmpty == true
                else { return }
                try? FileManager.default.removeItem(at: job.staging)
            }
            switch failure {
            case .password where password == nil || askingAtExtract:
                removeEmptyScratch()
                askingAtExtract = true
                try await askForPassword()
            case .noSpace where !inPlace && !keepOnly:
                let check = ArchiveCommandLine.check(archive: job.archive, staging: destination.staging)
                let plan = try await run(extractor, check, secret)
                guard await askInPlace(plan.output) else {
                    try? FileManager.default.removeItem(at: destination.staging)
                    throw failure
                }
                inPlace = true
                await onInPlace(true)
            case .resumeJournalMismatch:
                removeEmptyScratch()
                throw failure
            case .startedElsewhere(let path):
                removeEmptyScratch()
                guard !followedReportedPath, let staging = await resumeStaging(path) else { throw failure }
                followedReportedPath = true
                destination.staging = staging
            default:
                throw failure
            }
        }
        return try place(destination, stem: route.stem)
    }

    struct Abandoned: Sendable {
        var placed: URL?
        var stoppedSize: Int64?
    }

    @concurrent
    func abandon(_ job: ArchiveJob) async -> Abandoned {
        guard FileManager.default.fileExists(atPath: job.staging.path) else { return Abandoned() }
        if ArchiveRoute(fileName: job.name)?.engine == .hatchzip, let hatchzip = await locate(ArchiveTool.hatchzip.name) {
            let restore = ArchiveCommandLine.restore(archive: job.archive, staging: job.staging)
            let restored = try? await run(hatchzip, restore, [:])
            if !job.inPlace, restored?.status != 0,
                FileManager.default.fileExists(atPath: job.archive.path + ".hatchzip"),
                let size = Self.size(job.archive)
            {
                return Abandoned(stoppedSize: size)
            }
        }
        // Only HatchZip consumes the archive; another engine's half-written output is never saved work.
        guard job.inPlace, let route = ArchiveRoute(fileName: job.name), route.engine == .hatchzip else {
            try? FileManager.default.removeItem(at: job.staging)
            return Abandoned()
        }
        return Abandoned(placed: try? place(job, stem: route.stem))
    }

    /// Moves the staged items out by rename, so no byte is copied and nothing is overwritten.
    func place(_ job: ArchiveJob, stem: String) throws -> URL? {
        let files = FileManager.default
        let folder = job.archive.deletingLastPathComponent()
        let items = (try? files.contentsOfDirectory(atPath: job.staging.path)) ?? []
        let taken = { (name: String) in files.fileExists(atPath: folder.appending(path: name).path) }
        switch ArchivePlacement.plan(items: items.sorted(), stem: stem, taken: taken) {
        case .empty:
            try? files.removeItem(at: job.staging)
            return nil
        case .item(let item, let name):
            let target = folder.appending(path: name)
            try files.moveItem(at: job.staging.appending(path: item), to: target)
            try? files.removeItem(at: job.staging)
            return target
        case .folder(let name):
            let target = folder.appending(path: name, directoryHint: .isDirectory)
            try files.moveItem(at: job.staging, to: target)
            return target
        }
    }

    private func find(_ tool: ArchiveTool) async throws -> URL {
        guard let url = await locate(tool.name) else { throw ArchiveFailure.missingTool(tool) }
        return url
    }

    @concurrent
    static func pruneStaging(for job: ArchiveJob) async -> Bool {
        guard !Task.isCancelled else { return false }
        let files = FileManager.default
        do {
            _ = try files.attributesOfItem(atPath: job.archive.path)
            return false
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return await removeStaging(for: job)
        } catch {
            return false
        }
    }

    @concurrent
    static func removeStaging(for job: ArchiveJob) async -> Bool {
        guard !Task.isCancelled else { return false }
        do {
            try FileManager.default.removeItem(at: job.staging)
            return true
        } catch let error as CocoaError {
            return error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
        } catch {
            return false
        }
    }

    static func size(_ url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }

    private func hasLegacyNames(_ archive: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return false }
        let start = end > UInt64(ZIPNameEncoding.tailLength) ? end - UInt64(ZIPNameEncoding.tailLength) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let tail = try? handle.readToEnd(),
            let directory = ZIPNameEncoding.directory(tail: tail), directory.size <= 64 << 20,
            (try? handle.seek(toOffset: directory.offset)) != nil,
            let names = try? handle.read(upToCount: Int(directory.size))
        else { return false }
        return ZIPNameEncoding.hasLegacyNames(directory: names)
    }
}
