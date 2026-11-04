import Foundation

struct CleanSystemService<Transport: CleanSystemTransport> {
    enum Status: Equatable { case trashed, refused, changedOrMissing, failed(String) }
    struct Outcome {
        let path: String
        let status: Status
        let bytesFreed = 0
    }

    let policy: CleanSystemPolicy
    let transport: Transport

    func plan() throws -> CleanSystemPlan {
        var seen = Set<String>()
        let items = try transport.list(roots: policy.roots).compactMap { entry -> CleanSystemPlan.Item? in
            guard let reason = policy.reason(for: entry), seen.insert(entry.path).inserted else { return nil }
            return .init(entry: entry, reason: reason)
        }
        return CleanSystemPlan(items: items, snapshots: try transport.snapshots().map { .init(name: $0) })
    }

    func execute(_ selection: [String], from plan: CleanSystemPlan) -> [Outcome] {
        var seen = Set<String>()
        return selection.filter { seen.insert($0).inserted }.map { path in
            guard let item = plan.items.first(where: { $0.path == path }),
                  policy.reason(for: item.entry) != nil else {
                return Outcome(path: path, status: .refused)
            }
            do {
                guard let current = try transport.inspect(path: path), current == item.entry,
                      policy.reason(for: current) != nil else {
                    return Outcome(path: path, status: .changedOrMissing)
                }
                try transport.trash(current)
                return Outcome(path: path, status: .trashed)
            } catch {
                return Outcome(path: path, status: .failed(String(describing: error)))
            }
        }
    }
}
