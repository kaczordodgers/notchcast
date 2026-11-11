import Darwin
import Foundation

struct AgentSessionIndex: Sendable {
    struct Root: Sendable {
        let provider: AgentSession.Provider
        let url: URL

        static func defaults(home: URL) -> [Self] {
            let paths = AgentPaths(home: home)
            return paths.claudeProjects.map { Self(provider: .claude, url: $0) }
                + paths.codexSessions.map { Self(provider: .codex, url: $0) }
                + [Self(provider: .copilot, url: home.appendingPathComponent(".copilot/session-state")),
                   Self(provider: .opencode, url: home.appendingPathComponent(".local/share/opencode/opencode.db"))]
        }
    }

    struct Statistics: Sendable {
        var bytesRead = 0
        var largestRead = 0
        var filesRead = 0
        var malformedLines = 0
        var databaseRowsRead = 0
    }

    struct Issue: Sendable, Equatable {
        let url: URL
        let reason: String
    }

    struct Snapshot: Sendable {
        var sessions: [AgentSession] = []
        var issues: [Issue] = []
        var statistics = Statistics()
    }

    private struct Stamp: Sendable, Equatable {
        let inode: UInt64
        let size: Int64
        let modified: timespec

        static func == (left: Self, right: Self) -> Bool {
            left.inode == right.inode && left.size == right.size
                && left.modified.tv_sec == right.modified.tv_sec && left.modified.tv_nsec == right.modified.tv_nsec
        }
    }

    private struct Cursor: Sendable {
        var stamp: Stamp
        var offset: UInt64 = 0
        var pending = Data()
        var droppingLine = false
        var accumulator: AgentSessionAccumulator
    }

    static let chunkSize = 65_536
    static let maximumLineSize = 262_144
    private var cursors: [String: Cursor] = [:]
    private var databases: [String: AgentSessionDatabase] = [:]
    private let onAccess: @Sendable (URL) -> Void
    let calendar: Calendar
    var excludedPathComponentPrefixes: [String] = []

    init(calendar: Calendar = .current, onAccess: @escaping @Sendable (URL) -> Void = { _ in }) {
        self.onAccess = onAccess
        self.calendar = calendar
    }

    mutating func refresh(roots: [Root]) throws -> Snapshot {
        var snapshot = Snapshot()
        var seen: Set<String> = []
        for root in roots {
            try walk(root.url, provider: root.provider, seen: &seen, snapshot: &snapshot)
        }
        cursors = cursors.filter { seen.contains($0.key) }
        databases = databases.filter { seen.contains($0.key) }
        var sessions: [String: AgentSession] = [:]
        let files = cursors.keys.sorted().compactMap { path in
            cursors[path].map { (URL(fileURLWithPath: path).lastPathComponent, $0.accumulator.session) }
        } + databases.keys.sorted().flatMap { path in
            (databases[path]?.sessions ?? []).map { (URL(fileURLWithPath: path).lastPathComponent, $0) }
        }
        // A file copied between roots is one record; only differently named files add up.
        var copies: [String: AgentSession] = [:]
        for (name, session) in files {
            let key = session.id + "/" + name
            if (copies[key]?.lastActivityAt ?? .distantPast) <= (session.lastActivityAt ?? .distantPast) {
                copies[key] = session
            }
        }
        for session in copies.keys.sorted().compactMap({ copies[$0] }) where session.startedAt != nil {
            guard let existing = sessions[session.id] else {
                sessions[session.id] = session
                continue
            }
            var merged = (existing.lastActivityAt ?? .distantPast) >= (session.lastActivityAt ?? .distantPast)
                ? existing : session
            merged.project = merged.project ?? existing.project ?? session.project
            merged.model = merged.model ?? existing.model ?? session.model
            merged.endedAt = existing.endedAt.flatMap { left in session.endedAt.map { max(left, $0) } }
            merged.startedAt = min(existing.startedAt ?? .distantFuture, session.startedAt ?? .distantFuture)
            merged.usage = existing.usage
            for usage in session.usage {
                if let index = merged.usage.firstIndex(where: { $0.model == usage.model && $0.day == usage.day }) {
                    merged.usage[index].tokens += usage.tokens
                    if let cost = usage.reportedCost {
                        merged.usage[index].reportedCost = (merged.usage[index].reportedCost ?? 0) + cost
                    }
                } else {
                    merged.usage.append(usage)
                }
            }
            sessions[session.id] = merged
        }
        snapshot.sessions = sessions.values.sorted { $0.id < $1.id }
        return snapshot
    }

    static func allows(_ url: URL, excluding prefixes: [String]) -> Bool {
        !url.pathComponents.contains { component in
            let lowered = component.lowercased()
            return prefixes.contains { lowered.hasPrefix($0) }
        }
    }

    private func inspect(_ url: URL) throws -> stat? {
        guard Self.allows(url, excluding: excludedPathComponentPrefixes) else { return nil }
        var component = URL(fileURLWithPath: "/", isDirectory: true)
        var information = stat()
        for name in url.pathComponents.dropFirst() {
            component.appendPathComponent(name)
            onAccess(component)
            if lstat(component.path, &information) != 0 {
                if errno == ENOENT { return nil }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if information.st_mode & S_IFMT == S_IFLNK { throw POSIXError(.ELOOP) }
        }
        return information
    }

    private mutating func walk(_ url: URL, provider: AgentSession.Provider,
                               seen: inout Set<String>, snapshot: inout Snapshot) throws {
        try Task.checkCancellation()
        guard Self.allows(url, excluding: excludedPathComponentPrefixes) else { return }
        do {
            guard let information = try inspect(url) else { return }
            if information.st_mode & S_IFMT == S_IFDIR {
                guard provider != .opencode else { return }
                onAccess(url)
                let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                for child in children where Self.allows(child, excluding: excludedPathComponentPrefixes) {
                    try walk(child, provider: provider, seen: &seen, snapshot: &snapshot)
                }
                return
            }
            guard information.st_mode & S_IFMT == S_IFREG else { return }
            if provider == .opencode {
                guard url.lastPathComponent == "opencode.db" else { return }
                for suffix in ["-wal", "-shm", "-journal"] {
                    _ = try inspect(URL(fileURLWithPath: url.path + suffix))
                }
                seen.insert(url.path)
                var database = databases[url.path] ?? AgentSessionDatabase(calendar: calendar)
                try database.refresh(url: url, inode: information.st_ino, onAccess: onAccess)
                snapshot.statistics.databaseRowsRead += database.rowsRead
                databases[url.path] = database
            } else {
                guard url.pathExtension == "jsonl", provider != .copilot || url.lastPathComponent == "events.jsonl" else {
                    return
                }
                guard seen.insert(url.path).inserted else { return }
                try read(url, information: information, provider: provider, statistics: &snapshot.statistics)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            snapshot.issues.append(Issue(url: url, reason: String(describing: error)))
        }
    }

    private mutating func read(_ url: URL, information: stat, provider: AgentSession.Provider,
                               statistics: inout Statistics) throws {
        let stamp = Stamp(inode: information.st_ino, size: information.st_size, modified: information.st_mtimespec)
        var cursor = cursors[url.path]
        if cursor?.stamp == stamp { return }
        if cursor == nil || cursor?.stamp.inode != stamp.inode || UInt64(stamp.size) < cursor?.offset ?? 0
            || (cursor?.stamp.size == stamp.size && cursor?.stamp != stamp) {
            cursor = Cursor(stamp: stamp, accumulator: .init(provider: provider,
                id: provider.rawValue + ":" + url.deletingPathExtension().lastPathComponent, calendar: calendar))
        }
        guard var current = cursor else { return }
        onAccess(url)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, opened.st_ino == stamp.inode,
              opened.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.ESTALE) }
        try handle.seek(toOffset: current.offset)
        statistics.filesRead += 1
        while current.offset < UInt64(stamp.size) {
            try Task.checkCancellation()
            let length = min(Self.chunkSize, Int(UInt64(stamp.size) - current.offset))
            guard let chunk = try handle.read(upToCount: length), !chunk.isEmpty else { break }
            current.offset += UInt64(chunk.count)
            statistics.bytesRead += chunk.count
            statistics.largestRead = max(statistics.largestRead, chunk.count)
            consume(chunk, cursor: &current, statistics: &statistics)
        }
        if current.pending.isEmpty { current.pending = Data() }
        current.stamp = stamp
        cursors[url.path] = current
    }

    private func consume(_ chunk: Data, cursor: inout Cursor, statistics: inout Statistics) {
        var start = chunk.startIndex
        while start < chunk.endIndex {
            let newline = chunk[start...].firstIndex(of: 10)
            let end = newline ?? chunk.endIndex
            if !cursor.droppingLine {
                if cursor.pending.count + end - start > Self.maximumLineSize {
                    cursor.pending.removeAll(keepingCapacity: true)
                    cursor.droppingLine = true
                    statistics.malformedLines += 1
                } else {
                    cursor.pending.append(contentsOf: chunk[start..<end])
                }
            }
            if newline != nil {
                if !cursor.droppingLine && !cursor.pending.isEmpty && !cursor.accumulator.consume(cursor.pending) {
                    statistics.malformedLines += 1
                }
                cursor.pending.removeAll(keepingCapacity: true)
                cursor.droppingLine = false
            }
            start = newline.map { $0 + 1 } ?? chunk.endIndex
        }
    }
}
