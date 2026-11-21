import Foundation

/// Extracts opened archives from a journalled queue; compresses a Finder selection, one at a time.
@MainActor
final class ArchivesModule: NotchcastModule {
    static let switchID = "archives"
    static let defaultAppKey = "archivesDefaultApp"
    static let inPlaceKey = "archivesInPlace"
    /// Set once the archive types were claimed, so a later launch leaves the user's Finder choice alone.
    private static let claimedKey = "archivesClaimed"
    private static let noticeID = "archives.extracting"
    private static let compressNoticeID = "archives.compressing"

    private let context: NotchcastContext
    private let environment: ArchivesEnvironment
    private(set) var jobs: [ArchiveJob] = []
    private(set) var current: (job: ArchiveJob, task: Task<Void, Never>, resuming: UUID?)?
    private var pruning: Task<Void, Never>?
    /// `label` is nil while Finder's selection is still being read.
    private(set) var compression: (id: UUID, label: String?, task: Task<Void, Never>)?

    init(context: NotchcastContext, environment: ArchivesEnvironment) {
        self.context = context
        self.environment = environment
    }

    func start() {
        jobs = ArchiveJob.decode((try? Data(contentsOf: environment.journal)) ?? Data())
        pruneStoppedJobs()
        context.handleOpenURL { [weak self] url in
            guard let self, url.isFileURL, ArchiveRoute(fileName: url.lastPathComponent) != nil else { return false }
            open([url])
            return true
        }
        if context.defaults.bool(forKey: Self.defaultAppKey), !context.defaults.bool(forKey: Self.claimedKey) {
            setDefaultApp(true)
        }
        runNext()
    }

    /// A switch turned off gives the archive types back; quitting the app keeps them.
    func stop() {
        if !context.isEnabled(Self.switchID), context.defaults.bool(forKey: Self.defaultAppKey) {
            setDefaultApp(false)
        }
        pruning?.cancel()
        pruning = nil
        current?.task.cancel()
        current = nil
        context.presenter.end(notice: Self.noticeID)
        compression?.task.cancel()
        compression = nil
        context.presenter.end(notice: Self.compressNoticeID)
    }

    func open(_ urls: [URL]) {
        for url in urls {
            guard ArchiveRoute(fileName: url.lastPathComponent) != nil else {
                report(.notArchive(url.lastPathComponent))
                continue
            }
            guard !jobs.contains(where: { $0.archive.path == url.path && $0.stopped == nil }) else { continue }
            jobs.append(ArchiveJob(id: UUID(), archive: url, inPlace: context.defaults.bool(forKey: Self.inPlaceKey)))
        }
        save()
        runNext()
    }

    func pickAndOpen() { open(environment.pickArchives()) }

    func setDefaultApp(_ on: Bool) {
        context.defaults.set(on, forKey: Self.claimedKey)
        environment.setDefaultApp(on)
    }

    func cancel(_ id: UUID) {
        if current?.job.id == id {
            current?.task.cancel()
        } else {
            jobs.removeAll { $0.id == id && $0.stopped == nil }
            save()
        }
    }

    func cancelAll() {
        let running = current?.job.id
        // A stopped entry holds the only path its archive can still be extracted into.
        jobs.removeAll { $0.id != running && $0.stopped == nil }
        save()
        if let running { cancel(running) }
    }

    /// Waits for the queue to empty; the harness's only clock.
    func drain() async {
        while let task = pruning ?? current?.task { await task.value }
    }

    func drainCompression() async {
        while let task = compression?.task { await task.value }
    }

    /// Compresses Finder's selection into one archive beside it; extraction's queue runs on meanwhile.
    func compress(_ format: ArchiveFormat) {
        if let compression {
            // While the selection is still being read, a second press is the same request.
            if let label = compression.label { report(.busy(label)) }
            return
        }
        let id = UUID()
        let (readSelection, compressor) = (environment.finderSelection, environment.compressor)
        let task = Task { [weak self] in
            var label: String?
            do {
                let plan = try ArchiveCompression.plan(
                    format: format, selection: try await readSelection(), kind: ArchiveCompressor.kind,
                    isWritable: ArchiveCompressor.isWritable)
                try Task.checkCancellation()
                label = plan.label
                self?.compressionBegan(id, label: plan.label)
                let made = try await compressor.compress(plan)
                self?.compressionEnded(id, made: made)
            } catch is CancellationError {
                self?.compressionEnded(id, stopped: label)
            } catch {
                self?.compressionEnded(id, failure: error as? ArchiveFailure ?? .compressionFailed(error.localizedDescription))
            }
        }
        compression = (id, nil, task)
    }

    private func compressionBegan(_ id: UUID, label: String) {
        guard compression?.id == id else { return }
        compression?.label = label
        context.presenter.post(
            IslandNotice(id: Self.compressNoticeID, symbol: "doc.zipper",
                         text: String(localized: "Compressing \(label)", table: "NotchcastArchives"),
                         progress: IslandProgress(fraction: nil)),
            onTap: { [weak self] in self?.confirmStopCompression(id, label: label) })
    }

    private func compressionEnded(_ id: UUID, made: URL? = nil, failure: ArchiveFailure? = nil, stopped: String? = nil) {
        guard compression?.id == id else { return }
        compression = nil
        context.presenter.end(notice: Self.compressNoticeID)
        if let failure {
            report(failure)
        } else if let made {
            post(String(localized: "Compressed \(made.lastPathComponent)", table: "NotchcastArchives"),
                 symbol: "checkmark.circle", reveal: made)
        } else if let stopped {
            post(String(localized: "Stopped compressing \(stopped)", table: "NotchcastArchives"),
                 symbol: "xmark.circle", reveal: nil)
        }
    }

    private func confirmStopCompression(_ id: UUID, label: String) {
        guard let confirm = context.confirm else {
            if compression?.id == id { compression?.task.cancel() }
            return
        }
        Task {
            let title = String(localized: "Stop compressing \(label)?", table: "NotchcastArchives")
            let message = String(
                localized: "Nothing is kept. The selected files stay as they are.", table: "NotchcastArchives")
            guard await confirm(title, message, String(localized: "Stop", table: "NotchcastArchives")),
                compression?.id == id
            else { return }
            compression?.task.cancel()
        }
    }

    private func pruneStoppedJobs() {
        let cutoff = context.now().addingTimeInterval(-7 * 24 * 60 * 60)
        let candidates = jobs.filter { job in
            guard let stoppedAt = job.stopped?.stoppedAt else { return false }
            return stoppedAt < cutoff
        }
        guard !candidates.isEmpty else { return }
        pruning = Task { [weak self] in
            for job in candidates {
                let removed = await ArchiveExtractor.pruneStaging(for: job)
                guard !Task.isCancelled, let self else { return }
                if removed {
                    jobs.removeAll { $0.id == job.id }
                    save()
                }
            }
            self?.pruning = nil
            self?.runNext()
        }
    }

    private func resumeStaging(_ job: ArchiveJob, reportedPath: String?) async -> URL? {
        guard current?.job.id == job.id, !Task.isCancelled,
            let size = ArchiveExtractor.size(job.archive)
        else { return nil }
        let path: String?
        if let reportedPath {
            guard reportedPath.hasPrefix("/") else { return nil }
            path = URL(filePath: reportedPath).resolvingSymlinksInPath().path
        } else {
            path = nil
        }
        let entry = jobs.first {
            $0.archive.path == job.archive.path && $0.stopped?.size == size
                && (path == nil || $0.staging.resolvingSymlinksInPath().path == path)
        }
        guard let entry else { return nil }
        if !FileManager.default.fileExists(atPath: job.archive.path + ".hatchzip") {
            if await ArchiveExtractor.removeStaging(for: entry), current?.job.id == job.id, !Task.isCancelled {
                jobs.removeAll { $0.id == entry.id }
                save()
            }
            return nil
        }
        current?.resuming = entry.id
        return entry.staging
    }

    private func runNext() {
        guard pruning == nil, current == nil, let job = jobs.first(where: { $0.stopped == nil }) else { return }
        let extractor = environment.extractor
        let ask: ArchiveExtractor.AskInPlace = { [weak self] plan in await self?.askInPlace(job, plan: plan) ?? false }
        let password: ArchiveExtractor.AskPassword = { [weak self] wrong in await self?.askPassword(job, wrong: wrong) }
        let askPassword = context.askSecret == nil ? nil : password
        let markInPlace: @Sendable (Bool) async -> Void = { [weak self] on in await self?.markInPlace(job.id, on) }
        let task = Task { [weak self] in
            do {
                let placed = try await extractor.extract(
                    job, askPassword: askPassword, askInPlace: ask, onInPlace: markInPlace,
                    resumeStaging: { [weak self] path in await self?.resumeStaging(job, reportedPath: path) })
                self?.finish(job, placed: placed, failure: nil)
            } catch is CancellationError {
                await self?.stopped(job, failure: nil, extractor: extractor)
            } catch {
                let failure = error as? ArchiveFailure ?? .failed(error.localizedDescription)
                await self?.stopped(job, failure: failure, extractor: extractor)
            }
        }
        current = (job, task, nil)
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: "archivebox",
                         text: String(localized: "Extracting \(job.name)", table: "NotchcastArchives"),
                         progress: IslandProgress(fraction: nil)),
            onTap: { [weak self] in self?.confirmCancel(job) })
    }

    /// A stop or failure discards or salvages the job; after a module stop it stays to resume.
    private func stopped(_ job: ArchiveJob, failure: ArchiveFailure?, extractor: ArchiveExtractor) async {
        guard current?.job.id == job.id else { return }
        switch failure {
        case .startedElsewhere, .resumeJournalMismatch:
            finish(job, placed: nil, failure: failure)
            return
        default: break
        }
        if current?.resuming != nil {
            finish(job, placed: nil, failure: failure, cancelled: failure == nil)
            return
        }
        let job = latest(job)
        // A fresh task: this one is cancelled after a stop, which would refuse `hatchzip restore`.
        let left = await Task { await extractor.abandon(job) }.value
        finish(job, placed: left.placed, failure: failure, cancelled: failure == nil, stoppedSize: left.stoppedSize)
    }

    private func finish(
        _ job: ArchiveJob, placed: URL?, failure: ArchiveFailure?, cancelled: Bool = false,
        stoppedSize: Int64? = nil
    ) {
        guard current?.job.id == job.id else { return }
        let resumed = failure == nil && !cancelled ? current?.resuming : nil
        current = nil
        if let stoppedSize, let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index].stopped = ArchiveFingerprint(size: stoppedSize, stoppedAt: context.now())
        } else {
            jobs.removeAll { $0.id == job.id || $0.id == resumed }
        }
        save()
        context.presenter.end(notice: Self.noticeID)
        if let failure {
            report(failure, salvaged: placed)
        } else if cancelled {
            post(String(localized: "Stopped extracting \(job.name)", table: "NotchcastArchives"),
                 symbol: "xmark.circle", reveal: placed)
        } else if let placed {
            post(String(localized: "Extracted \(placed.lastPathComponent)", table: "NotchcastArchives"),
                 symbol: "checkmark.circle", reveal: placed)
        } else {
            post(String(localized: "\(job.name) is empty", table: "NotchcastArchives"), symbol: "archivebox", reveal: nil)
        }
        runNext()
    }

    private func report(_ failure: ArchiveFailure, salvaged: URL? = nil) {
        context.presenter.post(
            IslandNotice(id: "archives.failed", symbol: "exclamationmark.triangle", text: failure.message, isFailure: true),
            onTap: revealing(salvaged))
    }

    private func post(_ text: String, symbol: String, reveal url: URL?) {
        context.presenter.post(
            IslandNotice(id: "archives.done", symbol: symbol, text: text),
            onTap: revealing(url))
    }

    private func revealing(_ url: URL?) -> (@MainActor () -> Void)? {
        guard let url else { return nil }
        return { [weak self] in self?.environment.reveal(url) }
    }

    private func confirmCancel(_ job: ArchiveJob) {
        guard let confirm = context.confirm else { return cancel(job.id) }
        Task {
            let title = String(localized: "Stop extracting \(job.name)?", table: "NotchcastArchives")
            let message = String(
                localized: "A kept archive stays as it was. One extracted in place keeps what is already out.",
                table: "NotchcastArchives")
            guard await confirm(title, message, String(localized: "Stop", table: "NotchcastArchives")) else { return }
            cancel(job.id)
        }
    }

    private func askInPlace(_ job: ArchiveJob, plan: String) async -> Bool {
        guard current?.job.id == job.id, let confirm = context.confirm else { return false }
        let title = String(localized: "Not enough space to keep \(job.name)", table: "NotchcastArchives")
        let message = String(
            localized: "Extract in place instead? The archive is removed as its files come out.\n\n\(plan)",
            table: "NotchcastArchives")
        return await confirm(title, message, String(localized: "Extract in Place", table: "NotchcastArchives"))
    }

    /// Hands the answer straight back to the extractor; the module never keeps it.
    private func askPassword(_ job: ArchiveJob, wrong: Bool) async -> String? {
        guard current?.job.id == job.id, let askSecret = context.askSecret else { return nil }
        return await askSecret(
            String(localized: "Password for \(job.name)", table: "NotchcastArchives"),
            wrong ? String(localized: "That password did not work.", table: "NotchcastArchives") : nil,
            String(localized: "Password", table: "NotchcastArchives"),
            String(localized: "Extract", table: "NotchcastArchives"))
    }

    private func markInPlace(_ id: UUID, _ on: Bool) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].inPlace = on
        save()
    }

    /// The journal's copy, which knows whether the user switched it to in place.
    private func latest(_ job: ArchiveJob) -> ArchiveJob { jobs.first { $0.id == job.id } ?? job }

    private func save() {
        let folder = environment.journal.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? ArchiveJob.encode(jobs).write(to: environment.journal, options: .atomic)
    }
}
