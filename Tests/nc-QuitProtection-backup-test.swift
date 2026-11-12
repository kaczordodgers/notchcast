// notchcast-kit: core
// notchcast-sources: Tinycast/Features/QuitProtection/Model/*.swift
// notchcast-sources: Tinycast/Features/QuitProtection/Service/*.swift
// notchcast-sources: Tinycast/Features/QuitProtection/QuitProtectionStore+Shared.swift
// notchcast-sources: Tinycast/Features/QuitProtection/QuitProtectionBackupKeys.swift
import Foundation

@main
struct QuitProtectionBackupTests {
    @MainActor
    static func main() {
        let rule = NotchcastFeature.BackupKeys.quitProtection.allowed[QuitProtectionStore.modeKey]!
        precondition(QuitProtectionEngine.Mode.allCases.allSatisfy { rule.accepts($0.rawValue) })
        precondition(!rule.accepts("unknown") && !rule.accepts(1))
        print("PASS: backup accepts every Quit Protection mode and rejects unknown values and types")
    }
}
