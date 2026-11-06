import Foundation

struct CleanAIDataService: Sendable {
    let policy: CleanAIDataPolicy
    let transport: any CleanTrashTransport
    let git: any CleanAIDataGitReader
    let now: @Sendable () -> Date
    let chatIdle: @Sendable (URL) async -> Bool?
    let copy: @Sendable (URL, URL) throws -> Void

    @concurrent func scan() async throws -> [CleanAIDataItem] {
        let roots: [(String, CleanAIDataItem.Kind)] = [
            (".claude/projects", .claude), (".codex/sessions", .codex),
            (".local/share/opencode/storage/session", .openCode),
            (".claude/worktrees", .worktree), (".codex/worktrees", .worktree), ("agents/wt", .worktree)
        ]
        var result: [CleanAIDataItem] = []
        for (root, kind) in roots {
            var pending = [policy.home.appendingPathComponent(root)]
            while let path = pending.popLast() {
                try Task.checkCancellation()
                guard safe(path), let attributes = try? FileManager().attributesOfItem(atPath: path.path)
                else { continue }
                if policy.permits(path, kind: kind),
                   let snapshot = try? measure(path), old(snapshot.newest, kind: kind) {
                    let refusal = try await refusal(path, kind: kind)
                    result.append(CleanAIDataItem(path: path, kind: kind,
                        selectable: refusal == nil, refusal: refusal, snapshot: snapshot.values))
                } else if attributes[.type] as? FileAttributeType == .typeDirectory,
                          kind != .worktree || path.lastPathComponent == URL(fileURLWithPath: root).lastPathComponent {
                    pending += (try? FileManager().contentsOfDirectory(at: path,
                        includingPropertiesForKeys: nil)) ?? []
                }
            }
        }
        return result.sorted { $0.path.path < $1.path.path }
    }

    @concurrent func clean(_ selected: [CleanAIDataItem]) async throws -> [CleanAIDataOutcome] {
        var results: [CleanAIDataOutcome] = []
        for item in selected {
            try Task.checkCancellation()
            var recovery: URL?
            let status: CleanAIDataOutcome.Status
            do {
                guard item.selectable, policy.permits(item.path, kind: item.kind) else {
                    results.append(.init(path: item.path, status: .refused, recovery: nil)); continue
                }
                guard try await current(item) else {
                    results.append(.init(path: item.path, status: .changed, recovery: nil)); continue
                }
                if item.kind != .worktree {
                    let folder = policy.home.appendingPathComponent(".clean-ai-recovery")
                    if !FileManager().fileExists(atPath: folder.path) {
                        try FileManager().createDirectory(at: folder, withIntermediateDirectories: false)
                    }
                    guard safe(folder) else { throw CocoaError(.fileWriteNoPermission) }
                    let destination = folder.appendingPathComponent(UUID().uuidString)
                    let original = try Data(contentsOf: item.path)
                    try copy(item.path, destination)
                    guard safe(destination), try Data(contentsOf: destination) == original,
                          try Data(contentsOf: item.path) == original else {
                        results.append(.init(path: item.path, status: .recoveryFailed, recovery: nil)); continue
                    }
                    recovery = destination
                }
                guard try await current(item) else {
                    results.append(.init(path: item.path, status: .changed, recovery: recovery)); continue
                }
                try Task.checkCancellation()
                let metadata = item.kind == .worktree ? try worktreeMetadata(item.path) : nil
                try transport.trash(item.path)
                if let metadata { try git.removeWorktreeMetadata(metadata, worktree: item.path) }
                status = .trashed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                status = .failed(String(describing: error))
            }
            results.append(.init(path: item.path, status: status, recovery: recovery))
        }
        return results
    }

    private func current(_ item: CleanAIDataItem) async throws -> Bool {
        guard safe(item.path), policy.permits(item.path, kind: item.kind) else { return false }
        let snapshot = try measure(item.path)
        let permitted = try await refusal(item.path, kind: item.kind) == nil
        return snapshot.values == item.snapshot && old(snapshot.newest, kind: item.kind) && permitted
    }

    private func refusal(_ path: URL, kind: CleanAIDataItem.Kind) async throws -> CleanAIDataItem.Refusal? {
        if kind == .worktree {
            guard (try? worktreeMetadata(path)) != nil,
                  try await git.inspect(path)?.eligible == true else { return .gitStateUnverified }
            return nil
        }
        guard kind == .claude else { return .indexedStore }
        let project = path.deletingLastPathComponent()
        let sidecars = [project.appendingPathComponent("sessions-index.json"), path.deletingPathExtension()]
        guard !sidecars.contains(where: { FileManager().fileExists(atPath: $0.path) }) else {
            return .sessionSidecars
        }
        return await chatIdle(path) == true ? nil : .chatNotIdle
    }

    private func worktreeMetadata(_ path: URL) throws -> URL {
        let pointer = path.appendingPathComponent(".git")
        let attributes = try FileManager().attributesOfItem(atPath: pointer.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadNoPermission)
        }
        let text = try String(contentsOf: pointer, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("gitdir: ") else { throw CocoaError(.fileReadCorruptFile) }
        let value = String(text.dropFirst(8))
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\0") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let directory = URL(filePath: value, directoryHint: .isDirectory, relativeTo: path).standardized
        guard directory.deletingLastPathComponent().lastPathComponent == "worktrees" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try CleanAIDataWorktreeMetadata.verify(directory, worktree: path)
        return directory
    }

    private func old(_ date: Date, kind: CleanAIDataItem.Kind) -> Bool {
        now().timeIntervalSince(date) > max(kind == .worktree ? 86_400 : 0, policy.age)
    }

    private func safe(_ path: URL) -> Bool {
        guard path.path.hasPrefix(policy.home.path + "/") else { return false }
        var cursor = path
        while cursor.path != "/" {
            guard let attributes = try? FileManager().attributesOfItem(atPath: cursor.path),
                  attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return false }
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { return false }
            cursor = parent
        }
        return true
    }

    private func measure(_ path: URL) throws -> (values: [String: String], newest: Date) {
        var pending = [path]
        var values: [String: String] = [:]
        var newest = Date.distantPast
        while let entry = pending.popLast() {
            try Task.checkCancellation()
            guard safe(entry) else { throw CocoaError(.fileReadNoPermission) }
            let attributes = try FileManager().attributesOfItem(atPath: entry.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeDirectory else {
                throw CocoaError(.fileReadNoPermission)
            }
            newest = max(newest, attributes[.modificationDate] as? Date ?? .distantFuture)
            values[entry.path] = attributes.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { attribute in
                    let value = (attribute.value as? Date).map {
                        String($0.timeIntervalSinceReferenceDate.bitPattern)
                    } ?? String(describing: attribute.value)
                    return "\(attribute.key.rawValue)=\(value)"
                }.joined(separator: "|")
            if type == .typeDirectory {
                pending += try FileManager().contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
            }
        }
        return (values, newest)
    }
}
