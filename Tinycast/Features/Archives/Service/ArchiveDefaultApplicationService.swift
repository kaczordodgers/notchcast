import AppKit
import UniformTypeIdentifiers

@MainActor
struct ArchiveDefaultApplicationService: ArchiveDefaultApplicationSetting {
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
        let declarations = Bundle(url: target)?.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let supported = Set(declarations.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        var failures: [String] = []
        for identifier in ArchiveFormat.typeIdentifiers {
            if !enabled, !supported.contains(identifier) { continue }
            let type = UTType(importedAs: identifier)
            if !enabled, workspace.urlForApplication(toOpen: type)?.standardizedFileURL != application.standardizedFileURL {
                continue
            }
            do { try await workspace.setDefaultApplication(at: target, toOpen: type) } catch {
                failures.append("\(identifier): \(error)")
            }
        }
        if !failures.isEmpty { throw ArchiveFailure.filesystem(failures.joined(separator: "; ")) }
    }
}
