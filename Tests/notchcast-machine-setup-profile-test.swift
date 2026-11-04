// notchcast-sources: Tinycast/Features/MachineSetupProfile/Model/*.swift Tinycast/Features/MachineSetupProfile/Service/*.swift
import Foundation

@main
struct MachineSetupProfileTests {
    struct Fake: MachineSetupProfileExecutor {
        var applied = 0
        var reject = false
        func validateBackup(_ data: Data) throws {
            if data != Data("safe-backup".utf8) { throw MachineSetupProfileEngine.Failure.unsafeContent }
        }
        func validateDestinations(_ plan: MachineSetupProfileEngine.Plan) throws {
            if reject { throw MachineSetupProfileEngine.Failure.unsafeContent }
        }
        mutating func apply(_ plan: MachineSetupProfileEngine.Plan) throws { applied += 1 }
    }

    static func main() throws {
        let policy = MachineSetupProfileEngine.Policy(
            appVersion: "1", fileKeys: [".config/terminal.json": ["theme"]],
            moduleKeys: ["hoverDelay"], tweakIDs: ["dock.autohide"])
        func profile(path: String = ".config/terminal.json", value: String = "dark",
                     version: String = "1", backup: String = "safe-backup") -> MachineSetupProfile {
            .init(format: 1, appVersion: version, backup: Data(backup.utf8),
                  tweaks: ["dock.autohide"], files: [path: ["theme": value]], modules: ["hoverDelay": "0.3"])
        }
        func rejects(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection") } catch {}
        }
        var fake = Fake()
        let original = profile()
        let decoded = try JSONDecoder().decode(MachineSetupProfile.self, from: JSONEncoder().encode(original))
        precondition(decoded == original)
        let plan = try MachineSetupProfileRunner.run(decoded, policy: policy, enabled: true,
                                                     dryRun: true, confirmed: false, executor: &fake)
        precondition(fake.applied == 0 && plan.destinations.count == 4)
        rejects { _ = try MachineSetupProfileRunner.run(original, policy: policy, enabled: true,
                    dryRun: false, confirmed: false, executor: &fake) }
        for invalid in [profile(path: "../escape"), profile(path: "/tmp/file"),
                        profile(value: "api_token=abc"), profile(value: "/Users/example/file"),
                        profile(version: "2"), profile(backup: "invalid")] {
            rejects { _ = try MachineSetupProfileRunner.run(invalid, policy: policy, enabled: true,
                        dryRun: true, confirmed: false, executor: &fake) }
        }
        fake.reject = true
        rejects { _ = try MachineSetupProfileRunner.run(original, policy: policy, enabled: true,
                    dryRun: false, confirmed: true, executor: &fake) }
        fake.reject = false
        rejects { _ = try MachineSetupProfileRunner.run(original, policy: policy, enabled: false,
                    dryRun: false, confirmed: true, executor: &fake) }
        precondition(fake.applied == 0)
        _ = try MachineSetupProfileRunner.run(original, policy: policy, enabled: true,
                dryRun: false, confirmed: true, executor: &fake)
        precondition(fake.applied == 1)
        print("machine setup profile: PASS")
    }
}
