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
        try await Self.apply(enabled: enabled, application: application, supported: supported,
                             current: { workspace.urlForApplication(toOpen: UTType(importedAs: $0)) }) {
            try await workspace.setDefaultApplication(at: target, toOpen: UTType(importedAs: $0))
        }
    }

    static func apply(
        enabled: Bool, application: URL, supported: Set<String>,
        current: (String) -> URL?, set: (String) async throws -> Void
    ) async throws {
        var failures: [String] = []
        for identifier in ArchiveFormat.defaultTypeIdentifiers {
            if !enabled, !supported.contains(identifier) { continue }
            if !enabled, current(identifier)?.standardizedFileURL != application.standardizedFileURL {
                continue
            }
            do { try await set(identifier) } catch {
                failures.append("\(identifier): \(error)")
            }
        }
        if !failures.isEmpty { throw ArchiveFailure.filesystem(failures.joined(separator: "; ")) }
    }
}
