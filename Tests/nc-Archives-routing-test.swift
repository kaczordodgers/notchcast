// notchcast-sources: Tinycast/Features/Archives/Model/*.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-reads: Tinycast/Info.plist
import Foundation
import UniformTypeIdentifiers

@main
struct ArchiveRoutingTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let info = try Data(contentsOf: root.appending(path: "Tinycast/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any],
              let documents = plist["CFBundleDocumentTypes"] as? [[String: Any]],
              let imports = plist["UTImportedTypeDeclarations"] as? [[String: Any]] else {
            fatalError("Missing archive declarations")
        }
        guard let archives = documents.first(where: { $0["CFBundleTypeName"] as? String == "Archives" }) else {
            fatalError("Info.plist declares no Archives document type")
        }
        let identifiers = archives["LSItemContentTypes"] as? [String] ?? []
        var extensions: [String] = []
        for imported in imports {
            let tags = imported["UTTypeTagSpecification"] as? [String: Any]
            extensions += tags?["public.filename-extension"] as? [String] ?? []
        }
        var systemTypes = Set<String>()
        for path in [
            "/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist",
            "/System/Library/CoreServices/Applications/Archive Utility.app/Contents/Info.plist"
        ] {
            let data = try Data(contentsOf: URL(filePath: path))
            guard let system = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                fatalError("Missing system declarations")
            }
            for key in ["UTImportedTypeDeclarations", "UTExportedTypeDeclarations"] {
                let declarations = system[key] as? [[String: Any]] ?? []
                systemTypes.formUnion(declarations.compactMap { $0["UTTypeIdentifier"] as? String })
            }
        }
        let importedTypes = Set(imports.compactMap { $0["UTTypeIdentifier"] as? String })
        // ISO is declared by DiskImageMounter, outside the archive type declaration bundles.
        let archiveIdentifiers = Set(identifiers).subtracting(["public.iso-image"])
        let missing = archiveIdentifiers.subtracting(systemTypes).subtracting(importedTypes)
        precondition(missing.isEmpty, "Missing system or app declaration: \(missing.sorted())")
        let utilityURL = URL(fileURLWithPath: "/System/Library/CoreServices/Applications")
            .appending(path: "Archive Utility.app/Contents/Info.plist")
        guard let utility = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: utilityURL), format: nil) as? [String: Any],
              let utilityDocuments = utility["CFBundleDocumentTypes"] as? [[String: Any]] else {
            fatalError("Missing Archive Utility declarations")
        }
        let restorable = Set(utilityDocuments.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        let previousClaims: Set = ["com.rarlab.rar-archive", "app.notchcast.split-archive"]
        let expectedClaims = Set(identifiers).intersection(restorable).union(previousClaims)
        precondition(Set(ArchiveFormat.defaultTypeIdentifiers) == expectedClaims)
        precondition(previousClaims.isSubset(of: Set(ArchiveFormat.defaultTypeIdentifiers)))
        precondition(!ArchiveFormat.defaultTypeIdentifiers.contains("public.iso-image"))
        precondition(!ArchiveFormat.defaultTypeIdentifiers.contains("com.apple.installer-package-archive"))
        print("PASS: archive types declared by system plists or app imports; default claims preserve rar and 001")
        precondition(!extensions.contains("tar.gz"))
        guard let gzip = UTType(filenameExtension: "gz") else { fatalError("macOS names no type for .gz") }
        precondition(gzip.identifier == "org.gnu.gnu-zip-archive")
        precondition(identifiers.contains(gzip.identifier))
        precondition(!extensions.contains("gz"))
        let features: [NotchcastFeature] = [.archives, .archivesInPlace, .archivesDefaultApp]
        for feature in features {
            let entries = SettingsSearchCatalog.notchcast.filter {
                $0.title == feature.title && $0.anchor == .notchcastArchives
            }
            precondition(entries.count == 1 && entries[0].anchor == .notchcastArchives)
            precondition(entries[0].target == .row(.notchcastArchives, feature.title))
        }
        guard let result = SettingsSearchCatalog.results(for: "extract in place").first else {
            fatalError("Settings search finds nothing for \"extract in place\"")
        }
        precondition(result.title == NotchcastFeature.archivesInPlace.title && result.anchor == .notchcastArchives)
        precondition(SettingsSearchCatalog.results(for: "hatchzip").contains { $0.anchor == .notchcastArchives })
        let job = ArchiveJob(id: UUID(), archive: URL(fileURLWithPath: "/fixture/example.zip"))
        precondition(job.canCancel && !job.canRetry && !job.stateTitle.isEmpty)
        var fallback = job
        fallback.fallback = .inPlaceCheckRefused(1)
        precondition(fallback.fallbackNote != nil)
        fallback.fallback = .resumingKeepArchive
        precondition(fallback.fallbackNote != nil)
        fallback.fallback = nil
        fallback.effectiveMode = .inPlace
        fallback.state = .cancelled
        precondition(fallback.canRetry && !fallback.canCancel && fallback.fallbackNote != nil)
        print("PASS: gzip UTI probe, no compound or gzip extension tags, plain gzip support")
        print("PASS: one search entry per archive feature, search targets, job/failure presentation")
    }
}
