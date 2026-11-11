import AppKit
import Observation
import SQLite3
import Synchronization

@MainActor
final class CleanModule: NotchcastModule {
    nonisolated private static let history = CleanHistoryStore(
        logPath: NotchcastIdentity.supportRoot.appendingPathComponent("clean-history.jsonl"))
    private var running = false
    private weak var core: AppCore?
    private let preferences = NotchcastPreferences.shared
    lazy var coordinator = CleanCoordinator(
        transport: .init(scan: Self.scan),
        isOn: { [preferences] in preferences.isOn($0) },
        question: { [weak self] feature, count, bytes in
            let size = bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                ?? String(localized: "Unknown", table: "Notchcast")
            return await self?.ask(
                title: feature == .cleanHistory ? String(localized: "Restore", table: "Notchcast") : String(localized: "Move to trash", table: "Notchcast"),
                message: String(localized: "Continue with \(count) reviewed items, total size: \(size)?", table: "Notchcast")) ?? false
        }, optimizeQuestion: { [weak self] task in
            await self?.ask(title: task.title, message: task.question) ?? false
        }, report: { [weak self] error in
            self?.core?.showMessage(error.localizedDescription, tone: .danger)
        })

    func configure(_ core: AppCore) -> CleanModule {
        self.core = core
        return self
    }

    func start() {
        running = true
        observeSwitches()
    }

    func stop() {
        running = false
        coordinator.stop()
    }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        preferences.set(feature, enabled)
        coordinator.setEnabled(feature, enabled)
    }

    private func ask(title: String, message: String) async -> Bool {
        guard let core else { return false }
        return await core.choose(title: title, message: message, symbol: "trash",
            options: [DialogAction(title: String(localized: "Continue"), role: .destructive),
                      DialogAction(title: String(localized: "Cancel"), role: .cancel)],
            defaultIndex: 1, tone: .danger) == 0
    }

    private func observeSwitches() {
        guard running else { return }
        withObservationTracking {
            for feature in CleanCoordinator.features {
                coordinator.setEnabled(feature, preferences.isOn(feature))
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeSwitches() }
        }
    }

    @concurrent private static func scan(_ feature: NotchcastFeature, roots: [URL]) async throws
        -> CleanCoordinator.Review {
        try Task.checkCancellation()
        let home = FileManager().homeDirectoryForCurrentUser
        let trash = RecordedTrash(history: history, mode: feature.rawValue)
        switch feature {
        case .cleanJunk:
            let clock = Date.now
            let policy = { CleanPolicy(home: home, now: clock, logAge: 30 * 86_400, installerAge: 30 * 86_400,
                installedBundleIDs: $0, protectedNames: []) }
            let scanned = try await CleanService(policy: policy([]), transport: trash).scan()
            let installed = await installedBundleIDs(scanned)
            try Task.checkCancellation()
            let service = CleanService(policy: policy(installed), transport: trash)
            let items = scanned.filter { $0.category != .leftovers || !installed.contains($0.path.lastPathComponent) }
            trash.recordSizes(Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0.size) }))
            return .init(items: items.map { .init(id: $0.path, size: $0.size, reportOnly: $0.reportOnly) }) { paths in
                let outcomes = try await service.clean(items.filter { paths.contains($0.path) })
                guard outcomes.allSatisfy({ $0.status == .trashed }) else { throw Failure.itemsChanged }
            }
        case .cleanAIData:
            let service = CleanAIDataService(policy: .init(home: home, age: CleanAIDataPolicy.defaultAge),
                transport: trash, git: GitReader(), now: { .now },
                chatIdle: {
                    do { return try await Tools.idle($0) } catch { return nil }
                }, copy: { try FileManager().copyItem(at: $0, to: $1) })
            let items = try await service.scan()
            trash.recordSizes(Dictionary(uniqueKeysWithValues: items.map { ($0.path, snapshotSize($0.snapshot)) }))
            return .init(items: items.map {
                .init(id: $0.path, size: snapshotSize($0.snapshot), reportOnly: !$0.selectable)
            }) { paths in
                let outcomes = try await service.clean(items.filter { paths.contains($0.path) })
                guard outcomes.allSatisfy({ $0.status == .trashed }) else { throw Failure.itemsChanged }
            }
        case .cleanDisk:
            guard roots.count == 1, let root = roots.first else { throw Failure.itemsChanged }
            let scanner = CleanDiskScanner(root: root, limits: .init(), crossVolumes: false,
                now: { .now }, transport: trash)
            let scan = try await scanner.scan(id: UUID())
            trash.recordSizes(Dictionary(uniqueKeysWithValues: scan.nodes.map {
                ($0.path, Int64(clamping: $0.allocatedSize))
            }))
            return .init(items: scan.nodes.dropFirst().map {
                .init(id: $0.path, size: Int64(clamping: $0.allocatedSize), reportOnly: $0.unreadable)
            }) { paths in
                let selected = Set(paths)
                for index in scan.nodes.indices where selected.contains(scan.nodes[index].path) {
                    try await scanner.trash(index, from: scan, currentID: scan.id)
                }
            }
        case .cleanPurge:
            let service = CleanPurgeService(policy: .init(projectRoots: roots, now: .now,
                recentActivityThreshold: 7 * 86_400, maximumDepth: 32, maximumEntries: 100_000,
                protectedNames: []), transport: trash,
                activity: { project, _ in
                    switch try await Tools.idle(project, recursive: true) {
                    case true: .idle
                    case false: .active
                    case nil: .unknown
                    }
                }, lastActivity: {
                    try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .now
                })
            let items = try await service.scan()
            trash.recordSizes(Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0.allocatedSize) }))
            return .init(items: items.map {
                .init(id: $0.path, size: $0.allocatedSize, reportOnly: $0.activity != .idle)
            }) { paths in
                let outcomes = try await service.clean(items.filter { paths.contains($0.path) })
                guard outcomes.allSatisfy({ $0.status == .trashed }) else { throw Failure.itemsChanged }
            }
        case .cleanHistory:
            let entries = try history.read()
            return .init(items: entries.enumerated().map { index, entry in
                .init(id: URL(fileURLWithPath: entry.originalPath).appending(queryItems: [
                    URLQueryItem(name: "run", value: String(index))]), size: entry.size,
                    reportOnly: entry.status != .trashed || entry.trashPath.isEmpty,
                    detail: historyDetail(entry))
            }) { paths in
                for path in paths {
                    guard let index = URLComponents(url: path, resolvingAgainstBaseURL: false)?.queryItems?
                        .first(where: { $0.name == "run" })?.value.flatMap(Int.init), entries.indices.contains(index)
                    else { throw Failure.itemsChanged }
                    try Task.checkCancellation()
                    let entry = entries[index]
                    let restore = CleanHistoryRestore(originalRoots: [URL(fileURLWithPath: entry.originalPath)
                        .deletingLastPathComponent()], trashRoots: [URL(fileURLWithPath: entry.trashPath)
                        .deletingLastPathComponent()], log: history, now: { .now })
                    try restore.restore(entry)
                }
            }
        case .cleanOptimize:
            let tools = Tools()
            let service = CleanOptimizeService(home: home, quickLookTool: URL(fileURLWithPath: "/usr/bin/qlmanage"),
                openWithTool: URL(fileURLWithPath:
                    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"),
                process: tools, database: tools)
            return .init(items: CleanOptimizeTask.allCases.map {
                .init(id: URL(fileURLWithPath: "/clean-optimize/" + $0.rawValue), size: nil)
            }) { paths in
                let selected = Set(paths.compactMap { CleanOptimizeTask(rawValue: $0.lastPathComponent) })
                let outcomes = try await service.run(selected)
                guard outcomes.allSatisfy({
                    switch $0.status {
                    case .ran, .skipped: true
                    case .failed: false
                    }
                }) else { throw Failure.toolFailed }
            }
        case .cleanSystem:
            let client = CleanSystemRootClient(run: { try await RootHelperClient().clean($0, input: $1) },
                policy: .standard(now: .now))
            let entries = try await helper { try await client.list() }
            return .init(items: entries.map {
                .init(id: URL(fileURLWithPath: $0.path), size: $0.size)
            }) { paths in
                let selected = entries.filter { entry in paths.contains { $0.path == entry.path } }
                guard selected.count == paths.count else { throw Failure.itemsChanged }
                let skipped = try await helper { try await client.trash(selected) }
                if skipped > 0 { throw Failure.skipped(skipped) }
            }
        default: throw Failure.itemsChanged
        }
    }

    nonisolated private static func helper<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch CleanSystemRootClient.Failure.helperUpdate,
            RootHelperClient.Failure.reinstallRequired, RootHelperClient.Failure.unsafePath(.missing) {
            throw CleanCoordinator.HelperUpdate()
        }
    }

    nonisolated private static func snapshotSize(_ snapshot: [String: String]) -> Int64 {
        snapshot.values.filter { !$0.contains("NSFileType=NSFileTypeDirectory") }.reduce(0) { sum, value in
            sum + (value.split(separator: "|").first { $0.hasPrefix("NSFileSize=") }
                .flatMap { Int64($0.dropFirst("NSFileSize=".count)) } ?? 0)
        }
    }

    nonisolated private static func historyDetail(_ entry: CleanHistoryEntry) -> String {
        let status = switch entry.status {
        case .trashed: String(localized: "Moved to Trash")
        case .restored: String(localized: "Restored", table: "Notchcast")
        case .refused: String(localized: "Refused", table: "Notchcast")
        case .failed: String(localized: "Failed", table: "Notchcast")
        }
        let mode = entry.mode == "restore" ? String(localized: "Restore", table: "Notchcast")
            : NotchcastFeature(rawValue: entry.mode)?.title ?? String(localized: "Clean", table: "Notchcast")
        return "\(entry.time.formatted()) · \(mode) · \(status)"
    }

    private static func installedBundleIDs(_ items: [CleanItem]) -> Set<String> {
        Set(items.filter {
            $0.category == .leftovers
                && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.path.lastPathComponent) != nil
        }.map { $0.path.lastPathComponent })
    }

    private enum Failure: LocalizedError {
        case itemsChanged, toolFailed, skipped(Int)
        var errorDescription: String? {
            switch self {
            case .skipped(let count): String(localized: "\(count) entries skipped")
            case .itemsChanged: String(localized: "Some items changed or could not be processed. Scan again to review them.", table: "Notchcast")
            case .toolFailed: String(localized: "The Clean tool could not complete the request.", table: "Notchcast")
            }
        }
    }

    private final class RecordedTrash: CleanTrashTransport {
        let history: CleanHistoryStore
        let mode: String
        private let sizes = Mutex<[URL: Int64]>([:])

        init(history: CleanHistoryStore, mode: String) {
            self.history = history
            self.mode = mode
        }

        func recordSizes(_ values: [URL: Int64]) {
            sizes.withLock { $0 = values }
        }

        func trash(_ url: URL) throws {
            try Task.checkCancellation()
            var destination: NSURL?
            guard let size = sizes.withLock({ $0[url] }) else { throw Failure.itemsChanged }
            try FileManager().createDirectory(at: history.logPath.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try FileManager().trashItem(at: url, resultingItemURL: &destination)
            try history.recordTrash(.init(time: .now, mode: mode, size: size, status: .trashed,
                originalPath: url.path, trashPath: (destination as URL?)?.path ?? "")) {
                guard let destination = destination as URL? else { throw Failure.itemsChanged }
                try FileManager().moveItem(at: destination, to: url)
            }
        }
    }

    private struct GitReader: CleanAIDataGitReader {
        func removeWorktreeMetadata(_ directory: URL, worktree: URL) throws {
            try CleanAIDataWorktreeMetadata.remove(directory, worktree: worktree)
        }

        func inspect(_ path: URL) async throws -> CleanAIDataGitState? {
            do {
                return try await read(path)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return nil
            }
        }

        private func read(_ path: URL) async throws -> CleanAIDataGitState? {
            func git(_ arguments: [String]) async throws -> String {
                let result = try await CleanTool.run(URL(fileURLWithPath: "/usr/bin/git"),
                    ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", path.path] + arguments, timeout: 5)
                guard result.code == 0, result.error.isEmpty else { throw Failure.toolFailed }
                return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard try path.appendingPathComponent(".git").resourceValues(forKeys: [.isRegularFileKey])
                .isRegularFile == true else { return nil }
            let branch = try await git(["symbolic-ref", "--short", "HEAD"])
            guard !branch.isEmpty else { return nil }
            let common = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"])
            let gitDirectory = try await git(["rev-parse", "--absolute-git-dir"])
            guard common != gitDirectory else { return nil }
            let status = try await git(["status", "--porcelain=v1", "--untracked-files=all", "--ignored"])
            let ahead = try await git(["rev-list", "--count", "@{upstream}..HEAD"])
            let unmerged = try await git(["rev-list", "--count", "main..HEAD"])
            let flags = try await git(["ls-files", "-v"])
            let submodules = try await git(["submodule", "status", "--recursive"])
            let locked = FileManager().fileExists(atPath: gitDirectory + "/locked")
            let operation = ["index.lock", "HEAD.lock", "MERGE_HEAD", "CHERRY_PICK_HEAD", "rebase-merge", "rebase-apply"]
                .contains { FileManager().fileExists(atPath: gitDirectory + "/" + $0) }
            return .init(linked: true, locked: locked, dirty: !status.isEmpty, unpushed: ahead != "0",
                mergedIntoMain: unmerged == "0", hiddenIndexFlags: flags.split(separator: "\n").contains {
                    $0.first.map { $0 == "S" || $0.isLowercase } ?? true
                }, submodules: !submodules.isEmpty, operationInProgress: operation,
                idle: try await Tools.idle(path, recursive: true) == true)
        }
    }

    private struct Tools: CleanOptimizeProcessTransport, CleanOptimizeDatabaseTransport {
        @concurrent func run(_ request: CleanOptimizeRequest) async throws -> CleanOptimizeRequest.Result {
            .exited(try await CleanTool.run(request.executable, request.arguments, timeout: request.timeout).code)
        }

        @concurrent func count(at database: URL, timeout: TimeInterval) async throws -> Int {
            try Self.database(database, timeout: timeout, clear: false)
        }

        @concurrent func clear(at database: URL, timeout: TimeInterval) async throws -> Int {
            try Self.database(database, timeout: timeout, clear: true)
        }

        static func idle(_ path: URL, recursive: Bool = false) async throws -> Bool? {
            let result = try await CleanTool.run(URL(fileURLWithPath: "/usr/sbin/lsof"),
                ["-nP", "-t"] + (recursive ? ["+D", path.path] : ["--", path.path]), timeout: 5)
            guard result.error.isEmpty else { return nil }
            if result.code == 0 { return false }
            return result.code == 1 && result.output.isEmpty ? true : nil
        }

        static func database(_ url: URL, timeout: TimeInterval, clear: Bool) throws -> Int {
            try Task.checkCancellation()
            guard FileManager().fileExists(atPath: url.path) else { return 0 }
            guard url.standardizedFileURL == url.resolvingSymlinksInPath() else { throw Failure.toolFailed }
            var database: OpaquePointer?
            let flags = clear ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
            guard sqlite3_open_v2(url.path, &database, flags | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
                if let database { sqlite3_close(database) }
                throw Failure.toolFailed
            }
            defer { sqlite3_close(database) }
            sqlite3_busy_timeout(database, Int32(min(timeout, 5) * 1000))
            if clear {
                try Task.checkCancellation()
                guard sqlite3_exec(database, "DELETE FROM LSQuarantineEvent", nil, nil, nil) == SQLITE_OK
                else { throw Failure.toolFailed }
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM LSQuarantineEvent", -1, &statement, nil) == SQLITE_OK
            else { throw Failure.toolFailed }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw Failure.toolFailed }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }
}
