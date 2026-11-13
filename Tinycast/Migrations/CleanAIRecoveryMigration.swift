import Foundation
import OSLog

enum CleanAIRecoveryMigration {
    static func run(home: URL, defaults: UserDefaults, trash: (URL) throws -> Void) {
        let key = "cleanAIRecoveryRemoved"
        guard !defaults.bool(forKey: key) else { return }
        let folder = home.appendingPathComponent(".clean-ai-recovery")
        do {
            if FileManager().fileExists(atPath: folder.path) {
                guard CleanService.physical(folder, inside: home) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try trash(folder)
            }
            defaults.set(true, forKey: key)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.tinycast", category: "Clean")
                .error("Legacy AI recovery cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
