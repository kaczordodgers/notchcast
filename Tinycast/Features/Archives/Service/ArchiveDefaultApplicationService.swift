import AppKit
import UniformTypeIdentifiers

@MainActor
struct ArchiveDefaultApplicationService {
    func setEnabled(_ enabled: Bool, application: URL) async throws {
        let workspace = NSWorkspace.shared
        let target: URL
        if enabled {
            target = application
        } else {
            guard let utility = workspace.urlForApplication(withBundleIdentifier: "com.apple.archiveutility") else {
                throw ArchiveFailure.filesystem("Archive Utility unavailable")
            }
            target = utility
        }
        for identifier in ArchiveFormat.typeIdentifiers {
            let type = UTType(importedAs: identifier)
            if !enabled, workspace.urlForApplication(toOpen: type)?.standardizedFileURL != application.standardizedFileURL {
                continue
            }
            try await workspace.setDefaultApplication(at: target, toOpen: type)
        }
    }
}
