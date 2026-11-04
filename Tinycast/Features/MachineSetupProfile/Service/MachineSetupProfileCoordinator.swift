import Foundation

@MainActor
enum MachineSetupProfileCoordinator {
    struct Outcome: Sendable {
        let steps: [MachineSetupProfileProcessExecutor.Step]
        let succeeded: Bool
    }

    static func run(
        enabled: () -> Bool,
        preview: () async -> Outcome,
        confirm: ([MachineSetupProfileProcessExecutor.Step]) async -> Bool,
        apply: () async -> Outcome,
        present: (Outcome) -> Void
    ) async {
        guard enabled() else { return }
        let planned = await preview()
        guard enabled() else { return }
        guard planned.succeeded else { return present(planned) }
        guard planned.steps.contains(where: { $0.status == .planned }) else { return present(planned) }
        guard await confirm(planned.steps), enabled() else { return }
        let result = await apply()
        present(result)
    }

    @concurrent
    static func execute(_ profile: MachineSetupProfile, version: String, dryRun: Bool) async -> Outcome {
        var executor = MachineSetupProfileProcessExecutor.live()
        do {
            let policy = MachineSetupProfileEngine.Policy(appVersion: version, fileKeys: [:],
                moduleKeys: [], tweakIDs: MachineSetupProfileProcessExecutor.tweakIDs)
            let plan = try MachineSetupProfileRunner.run(profile, policy: policy, enabled: true,
                dryRun: true, confirmed: false, executor: &executor)
            if dryRun {
                try executor.preview(plan)
            } else {
                _ = try MachineSetupProfileRunner.run(profile, policy: policy, enabled: true,
                    dryRun: false, confirmed: true, executor: &executor)
            }
            return Outcome(steps: executor.report, succeeded: true)
        } catch {
            return Outcome(steps: executor.report, succeeded: false)
        }
    }

    @concurrent
    static func read(_ file: URL) async throws -> MachineSetupProfile {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 1_048_576 else {
            throw MachineSetupProfileEngine.Failure.unsafeContent
        }
        return try JSONDecoder().decode(MachineSetupProfile.self, from: Data(contentsOf: file))
    }
}
