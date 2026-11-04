import Foundation

protocol MachineSetupProfileExecutor {
    func validateBackup(_ data: Data) throws
    func validateDestinations(_ plan: MachineSetupProfileEngine.Plan) throws
    mutating func apply(_ plan: MachineSetupProfileEngine.Plan) throws
}

enum MachineSetupProfileRunner {
    static func run<Executor: MachineSetupProfileExecutor>(
        _ profile: MachineSetupProfile, policy: MachineSetupProfileEngine.Policy,
        enabled: Bool, dryRun: Bool, confirmed: Bool, executor: inout Executor
    ) throws -> MachineSetupProfileEngine.Plan {
        guard enabled else { throw MachineSetupProfileEngine.Failure.disabled }
        let plan = try MachineSetupProfileEngine.plan(profile, policy: policy)
        try executor.validateBackup(profile.backup)
        try executor.validateDestinations(plan)
        if !dryRun {
            guard confirmed else { throw MachineSetupProfileEngine.Failure.consentRequired }
            try executor.apply(plan)
        }
        return plan
    }
}
