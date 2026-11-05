// notchcast-sources: Tinycast/Features/Archives/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
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
            let tags = imported["UTTypeTagSpecification"] as? [String: Any]
            extensions += tags?["public.filename-extension"] as? [String] ?? []
        }
        precondition(Set(["7z", "rar", "tgz", "001"]).isSubset(of: Set(extensions)))
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
        let failures: [ArchiveFailure] = [
            .toolMissing, .unsupportedFormat, .invalidListing, .unsafePath("../bad"), .collision("A"),
            .symlinkAncestor("link/file"), .tooManyEntries, .expansionLimit, .insufficientSpace,
            .passwordRequired, .damagedArchive, .existingProgress, .toolFailed(4), .filesystem("fixture")
        ]
        precondition(failures.allSatisfy { !$0.message.isEmpty })
        print("PASS: archive document types, alternate rank, gzip UTI probe, split tags, plain gz routing refusal")
        print("PASS: deferred open-file hook, quit hook, one settings section, search targets, job/failure presentation")
    }
}
