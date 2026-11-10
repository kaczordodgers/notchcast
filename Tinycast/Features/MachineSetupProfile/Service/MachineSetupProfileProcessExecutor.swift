import Foundation

struct MachineSetupProfileProcessExecutor: MachineSetupProfileExecutor {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    enum Status: String, Sendable {
        case planned, satisfied, applied, needsHelper, failed, notRun
    }

    struct Step: Equatable, Sendable {
        let id: String
        let status: Status
    }

    enum Failure: Error { case unsupportedPayload, rootExecution, stepFailed }

    typealias Launch = (String, [String]) throws -> Result
    let process: Launch
    let isRoot: () -> Bool
    private(set) var report: [Step] = []

    static let tweakIDs: Set<String> = ["dock.autohide", "system.firewall"]

    func validateBackup(_ data: Data) throws {
        guard data.isEmpty else { throw Failure.unsupportedPayload }
    }

    func validateDestinations(_ plan: MachineSetupProfileEngine.Plan) throws {
        try validateBackup(plan.profile.backup)
        guard plan.profile.files.isEmpty, plan.profile.modules.isEmpty,
              Set(plan.profile.tweaks).count == plan.profile.tweaks.count,
              Set(plan.profile.tweaks).isSubset(of: Self.tweakIDs)
        else { throw Failure.unsupportedPayload }
    }

    mutating func preview(_ plan: MachineSetupProfileEngine.Plan) throws {
        try execute(plan, dryRun: true)
    }

    mutating func apply(_ plan: MachineSetupProfileEngine.Plan) throws {
        try execute(plan, dryRun: false)
    }

    private mutating func execute(_ plan: MachineSetupProfileEngine.Plan, dryRun: Bool) throws {
        report = []
        try validateDestinations(plan)
        guard !isRoot() else { throw Failure.rootExecution }
        let ids = plan.profile.tweaks.sorted()
        for (index, id) in ids.enumerated() {
            if id == "system.firewall" {
                report.append(Step(id: id, status: .needsHelper))
                continue
            }
            do {
                let current = try process("/usr/bin/defaults", ["read", "com.apple.dock", "autohide"])
                guard [0, 1].contains(current.status) else { throw Failure.stepFailed }
                let value = current.status == 1 ? "0"
                    : current.output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard ["0", "1"].contains(value) else { throw Failure.stepFailed }
                if value == "1" {
                    report.append(Step(id: id, status: .satisfied))
                } else if dryRun {
                    report.append(Step(id: id, status: .planned))
                } else {
                    guard !isRoot() else { throw Failure.rootExecution }
                    let result = try process("/usr/bin/defaults",
                                             ["write", "com.apple.dock", "autohide", "-bool", "true"])
                    guard result.status == 0 else { throw Failure.stepFailed }
                    let restarted = try process("/usr/bin/killall", ["Dock"])
                    guard restarted.status == 0 else { throw Failure.stepFailed }
                    let verified = try process("/usr/bin/defaults", ["read", "com.apple.dock", "autohide"])
                    guard verified.status == 0,
                          verified.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                    else { throw Failure.stepFailed }
                    report.append(Step(id: id, status: .applied))
                }
            } catch {
                report.append(Step(id: id, status: .failed))
                report.append(contentsOf: ids.dropFirst(index + 1).map { Step(id: $0, status: .notRun) })
                throw Failure.stepFailed
            }
        }
    }
}
