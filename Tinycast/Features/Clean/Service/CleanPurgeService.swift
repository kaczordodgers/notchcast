import Foundation

struct CleanPurgeService: Sendable {
    struct Outcome: Sendable {
        let item: CleanPurgeItem
        let status: CleanOutcome.Status
    }

    let policy: CleanPurgePolicy
    let transport: any CleanTrashTransport
    let activity: @Sendable (URL, URL) async throws -> CleanPurgeItem.Activity
    let lastActivity: @Sendable (URL) throws -> Date
    private let authority = UUID()

    @concurrent func scan() async throws -> [CleanPurgeItem] {
        let manager = FileManager()
        var found: [CleanPurgeItem] = []
        var visited = Set<URL>()
        var count = 0
        for root in policy.projectRoots {
            guard safe(root, manager: manager) else { continue }
            var pending = [(root, 0)]
            while let (project, depth) = pending.popLast() {
                try Task.checkCancellation()
                guard visited.insert(project).inserted else { continue }
                count += 1
                guard count <= policy.maximumEntries else { throw CocoaError(.fileReadTooLarge) }
                guard depth <= policy.maximumDepth else { throw CocoaError(.fileReadTooLarge) }
                for child in try manager.contentsOfDirectory(at: project, includingPropertiesForKeys: nil) {
                    try Task.checkCancellation()
                    guard policy.permits(child), safe(child, manager: manager),
                          isDirectory(child, manager: manager) else { continue }
                    if let rule = CleanPurgeRule.allCases.first(where: { $0.folder == child.lastPathComponent }) {
                        guard confirmed(rule, project: project, manager: manager),
                              let measured = try measure(child, manager: manager) else { continue }
                        let state: CleanPurgeItem.Activity
                        do { state = try await activity(project, child) }
                        catch is CancellationError { throw CancellationError() }
                        catch { state = .unknown }
                        let recent = policy.now.timeIntervalSince(try lastActivity(project))
                            <= max(0, policy.recentActivityThreshold)
                        found.append(CleanPurgeItem(project: project, path: child, rule: rule,
                            allocatedSize: measured.size, activity: state, recentlyActive: recent,
                            authority: authority, snapshot: measured.snapshot))
                    } else if !child.lastPathComponent.hasPrefix("."),
                              !manager.fileExists(atPath: child.appendingPathComponent(".git").path) {
                        pending.append((child, depth + 1))
                    }
                }
            }
        }
        try Task.checkCancellation()
        return found.sorted { $0.path.path < $1.path.path }
    }

    @concurrent func clean(_ selected: [CleanPurgeItem]) async throws -> [Outcome] {
        let manager = FileManager()
        var outcomes: [Outcome] = []
        var visited = Set<URL>()
        for item in selected {
            try Task.checkCancellation()
            guard visited.insert(item.path).inserted else { continue }
            guard item.authority == authority, policy.permits(item.path),
                  item.path.standardizedFileURL.path
                    == item.project.appendingPathComponent(item.rule.folder).standardizedFileURL.path else {
                outcomes.append(Outcome(item: item, status: .refused))
                continue
            }
            do {
                guard safe(item.path, manager: manager),
                      repositoryBoundary(item.project, manager: manager),
                      confirmed(item.rule, project: item.project, manager: manager),
                      try await activity(item.project, item.path) == .idle,
                      let current = try measure(item.path, manager: manager),
                      current.snapshot == item.snapshot else {
                    outcomes.append(Outcome(item: item, status: .changedOrMissing))
                    continue
                }
                try Task.checkCancellation()
                try transport.trash(item.path)
                outcomes.append(Outcome(item: item, status: .trashed))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                outcomes.append(Outcome(item: item, status: .failed(String(describing: error))))
            }
        }
        return outcomes
    }

    private func confirmed(_ rule: CleanPurgeRule, project: URL, manager: FileManager) -> Bool {
        func regular(_ name: String) -> Bool {
            let url = project.appendingPathComponent(name)
            return safe(url, manager: manager)
                && (try? manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
        }
        return regular(rule.marker) && rule.lockfiles.contains(where: regular)
    }

    private func repositoryBoundary(_ project: URL, manager: FileManager) -> Bool {
        var current = project
        while !policy.projectRoots.contains(where: {
            $0.standardizedFileURL.path == current.standardizedFileURL.path
        }) {
            guard policy.permits(current),
                  !manager.fileExists(atPath: current.appendingPathComponent(".git").path) else { return false }
            current.deleteLastPathComponent()
        }
        return true
    }

    private func safe(_ url: URL, manager: FileManager) -> Bool {
        var current = URL(fileURLWithPath: "/")
        var components = Array(url.pathComponents.dropFirst())
        if components.first == "var" || components.first == "tmp" { components.insert("private", at: 0) }
        for component in components {
            current.appendPathComponent(component)
            guard let attributes = try? manager.attributesOfItem(atPath: current.path),
                  attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return false }
        }
        return true
    }

    private func isDirectory(_ url: URL, manager: FileManager) -> Bool {
        (try? manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }

    private func measure(_ root: URL, manager: FileManager) throws
        -> (size: Int64, snapshot: [String: String])? {
        var pending = [root]
        var snapshot: [String: String] = [:]
        var size: Int64 = 0
        while let url = pending.popLast() {
            try Task.checkCancellation()
            guard snapshot.count < policy.maximumEntries, policy.permits(url),
                  safe(url, manager: manager) else { return nil }
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeRegular,
                  attributes[.immutable] as? Bool != true,
                  attributes[.appendOnly] as? Bool != true else { return nil }
            snapshot[url.standardizedFileURL.path] = attributes.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { attribute in
                    let value = (attribute.value as? Date).map {
                        String($0.timeIntervalSinceReferenceDate.bitPattern)
                    } ?? String(describing: attribute.value)
                    return "\(attribute.key.rawValue)=\(value)"
                }.joined(separator: "|")
            if type == .typeDirectory {
                let children = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                guard !children.contains(where: { $0.lastPathComponent == ".git" }) else { return nil }
                pending += children
            } else {
                let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                guard let allocated = values.totalFileAllocatedSize else { return nil }
                size += Int64(allocated)
            }
        }
        return (size, snapshot)
    }
}
