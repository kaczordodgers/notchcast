import Foundation

struct CleanSystemPlan: Sendable {
    enum Reason: Sendable { case agedCache, rotatedLog, diagnosticReport, unifiedLog }
    enum Action: Sendable { case trash }

    struct Item: Sendable {
        let entry: CleanSystemEntry
        let reason: Reason
        var path: String { entry.path }
        var size: Int64 { entry.size }
        var action: Action { .trash }
    }

    struct Snapshot: Sendable {
        let name: String
        var action: Action? { nil }
    }

    let items: [Item]
    let snapshots: [Snapshot]
}
