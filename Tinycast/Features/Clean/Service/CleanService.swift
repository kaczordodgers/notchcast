import Foundation

struct CleanService: Sendable {
    let policy: CleanPolicy
    let transport: any CleanTrashTransport

    @concurrent func scan() async throws -> [CleanItem] {
        let manager = FileManager()
        var items: [CleanItem] = []
        for category in CleanCategory.allCases {
            try Task.checkCancellation()
            let root = policy.home.appendingPathComponent(category.relativeRoot)
            guard safeAncestors(root, manager: manager) else { continue }
            if category == .trash {
                if let measured = try? measure(root, manager: manager) {
                    items.append(CleanItem(category: category, path: root, size: measured.size,
                                           reportOnly: true, snapshot: measured.snapshot))
                }
                continue
            }
            guard let children = try? manager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                guard policy.permits(child.path, category: category),
                      safeAncestors(child, manager: manager),
                      let measured = try? measure(child, manager: manager, category: category),
                      policy.eligible(child, category: category, newest: measured.newest) else { continue }
                items.append(CleanItem(category: category, path: child.standardizedFileURL, size: measured.size,
                                       reportOnly: false, snapshot: measured.snapshot))
            }
        }
        try Task.checkCancellation()
        return items
    }

    @concurrent func clean(_ selected: [CleanItem]) async throws -> [CleanOutcome] {
        let manager = FileManager()
        var outcomes: [CleanOutcome] = []
        for item in selected {
            try Task.checkCancellation()
            let status: CleanOutcome.Status
            if item.reportOnly || !policy.permits(item.path.path, category: item.category) {
                status = .refused
            } else if !safeAncestors(item.path, manager: manager) {
                status = .changedOrMissing
            } else {
                do {
                    let current = try measure(item.path, manager: manager, category: item.category)
                    guard current.snapshot == item.snapshot,
                          policy.eligible(item.path, category: item.category, newest: current.newest)
                    else {
                        outcomes.append(CleanOutcome(item: item, status: .changedOrMissing, bytesMoved: 0))
                        continue
                    }
                    try Task.checkCancellation()
                    try transport.trash(item.path)
                    status = .trashed
                } catch is CancellationError {
                    throw CancellationError()
                } catch CocoaError.fileReadNoSuchFile {
                    status = .changedOrMissing
                } catch {
                    status = .failed(String(describing: error))
                }
            }
            outcomes.append(CleanOutcome(item: item, status: status,
                                         bytesMoved: status == .trashed ? item.size : 0))
        }
        return outcomes
    }

    private func safeAncestors(_ url: URL, manager: FileManager) -> Bool {
        let home = policy.home.standardizedFileURL
        guard home == home.resolvingSymlinksInPath(),
              url.standardizedFileURL.path.hasPrefix(home.path + "/") else { return false }
        var current = url.standardizedFileURL
        while current.path.hasPrefix(home.path) {
            guard let attributes = try? manager.attributesOfItem(atPath: current.path),
                  attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return false }
            if current == home { return true }
            current.deleteLastPathComponent()
        }
        return false
    }

    private func measure(_ url: URL, manager: FileManager, category: CleanCategory? = nil) throws
        -> (size: Int64, newest: Date, snapshot: [String: String]) {
        var pending = [url]
        var size: Int64 = 0
        var newest = Date.distantPast
        var snapshot: [String: String] = [:]
        while let entry = pending.popLast() {
            try Task.checkCancellation()
            if let category, !policy.permits(entry.path, category: category) {
                throw CocoaError(.fileReadNoPermission)
            }
            let attributes = try manager.attributesOfItem(atPath: entry.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeRegular,
                  attributes[.immutable] as? Bool != true,
                  attributes[.appendOnly] as? Bool != true else { throw CocoaError(.fileReadNoPermission) }
            let modified = attributes[.modificationDate] as? Date ?? .distantFuture
            newest = max(newest, modified)
            snapshot[entry.standardizedFileURL.path] = attributes.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { attribute in
                    let value = (attribute.value as? Date).map {
                        String($0.timeIntervalSinceReferenceDate.bitPattern)
                    } ?? String(describing: attribute.value)
                    return "\(attribute.key.rawValue)=\(value)"
                }.joined(separator: "|")
            if type == .typeDirectory {
                pending += try manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
            } else {
                size += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        return (size, newest, snapshot)
    }
}
