// notchcast-sources: Tinycast/Features/Archives/Model/*.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-reads: Tinycast/Info.plist Tinycast/App/AppCore.swift Tinycast/App/AppDelegate.swift
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
        let archiveTypes = documents.filter { $0["CFBundleTypeName"] as? String == "Archives" }
        precondition(archiveTypes.count == 1)
        precondition(archiveTypes[0]["LSHandlerRank"] as? String == "Alternate")
        let identifiers = archiveTypes[0]["LSItemContentTypes"] as? [String] ?? []
        precondition(Set(identifiers) == Set(ArchiveFormat.typeIdentifiers))
        var extensions: [String] = []
        for imported in imports {
            let identifier = imported["UTTypeIdentifier"] as? String ?? ""
            precondition(identifier.hasPrefix("app.notchcast.") || identifier == "org.bittorrent.torrent"
                         || identifier == "com.rarlab.rar-archive")
            let tags = imported["UTTypeTagSpecification"] as? [String: Any]
            extensions += tags?["public.filename-extension"] as? [String] ?? []
        }
        precondition(extensions.contains("001"))
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
        let gzip = UTType(filenameExtension: "gz")!
        precondition(gzip.identifier == "org.gnu.gnu-zip-archive")
        precondition(identifiers.contains(gzip.identifier))
        precondition(!extensions.contains("gz"))
        let core = try String(contentsOf: root.appending(path: "Tinycast/App/AppCore.swift"), encoding: .utf8)
        let route = core.components(separatedBy: "func handleOpenURL(_ url: URL)")[1]
        let pending = route.range(of: "if pendingURLs != nil")!
        let archives = route.range(of: "if NotchcastCore.archives.open(url) { return }")!
        let existing = route.range(of: "if deepLinkCoordinator.handles(url)")!
        precondition(pending.lowerBound < archives.lowerBound && archives.lowerBound < existing.lowerBound)
        precondition(core.contains("await NotchcastCore.archives.prepareForTermination()"))
        let delegate = try String(contentsOf: root.appending(path: "Tinycast/App/AppDelegate.swift"), encoding: .utf8)
        precondition(delegate.contains("for url in urls") && delegate.contains("AppCore.shared.handleOpenURL(url)"))
        let features: [NotchcastFeature] = [.archives, .archivesInPlace, .archivesDefaultApp]
        for feature in features {
            precondition(feature.settingsGroup == .archives)
            let entries = SettingsSearchCatalog.notchcast.filter {
                $0.title == feature.title && $0.anchor == .notchcastArchives
            }
            precondition(entries.count == 1 && entries[0].anchor == .notchcastArchives)
            precondition(entries[0].target == .row(.notchcastArchives, feature.title))
        }
        let result = SettingsSearchCatalog.results(for: "extract in place").first!
        precondition(result.title == NotchcastFeature.archivesInPlace.title && result.anchor == .notchcastArchives)
        precondition(SettingsSearchCatalog.results(for: "hatchzip").contains { $0.anchor == .notchcastArchives })
        precondition(NotchcastSettingsModule.module(of: .archives) == .filesAndClipboard)
        precondition(NotchcastSettingsModule.module(of: .archivesInPlace) == .filesAndClipboard)
        precondition(NotchcastSettingsModule.module(of: .archivesDefaultApp) == .filesAndClipboard)
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
        print("PASS: archive document types, alternate rank, gzip UTI probe, split tags, plain gzip support")
        print("PASS: deferred open-file hook, quit hook, one settings section, search targets, job/failure presentation")
    }
}
