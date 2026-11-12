import Foundation

extension MachineSetupProfileCoordinator {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "machine-setup-profile", name: String(localized: "Machine Setup Profile", table: "Notchcast"),
        sfSymbol: "square.and.arrow.down", feature: .machineSetupProfile,
        isEnabled: { NotchcastPreferences.shared.isOn(.machineSetupProfile) },
        run: {
            guard let file = BackupActions.chooseJSONFile() else { return }
            Task { await importProfile(file) }
        })

    private static func importProfile(_ file: URL) async {
        let host = NotchcastHost.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        do {
            let profile = try await read(file)
            await run(
                enabled: { NotchcastPreferences.shared.isOn(.machineSetupProfile) },
                preview: { await execute(profile, version: version, dryRun: true) },
                confirm: { steps in
                    await host.confirm(String(localized: "Machine Setup Profile", table: "Notchcast"),
                        report(steps), "square.and.arrow.down", String(localized: "Apply"))
                },
                apply: { await execute(profile, version: version, dryRun: false) },
                present: { outcome in
                    host.showMessage(outcome.succeeded ? report(outcome.steps) :
                        String(localized: "Import Failed") + "\n" + report(outcome.steps),
                        outcome.succeeded ? .success : .danger)
                })
        } catch {
            host.showMessage(String(localized: "Import Failed"), .danger)
        }
    }

    private static func report(_ steps: [MachineSetupProfileProcessExecutor.Step]) -> String {
        steps.map { step in
            let status: String = switch step.status {
            case .planned: String(localized: "Planned", table: "Notchcast")
            case .satisfied: String(localized: "Already satisfied", table: "Notchcast")
            case .applied: String(localized: "Applied", table: "Notchcast")
            case .needsHelper: String(localized: "Needs helper", table: "Notchcast")
            case .failed: String(localized: "Failed", table: "Notchcast")
            case .notRun: String(localized: "Not run", table: "Notchcast")
            }
            return step.id + ": " + status
        }.joined(separator: "\n")
    }
}
