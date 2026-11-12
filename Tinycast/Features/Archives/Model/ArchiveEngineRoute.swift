import Foundation

nonisolated enum ArchiveEngineRoute: Equatable, Sendable {
    case hatchzip
    case bsdtar
    case zstd
    case xad

    static func route(_ url: URL, windowsZIP: Bool = false) -> Self? {
        guard let match = ArchiveFormat.match(url.lastPathComponent) else { return nil }
        return windowsZIP && url.lastPathComponent.lowercased().hasSuffix(".zip") ? .xad : match.entry.route
    }

    static func isSingleStream(_ url: URL) -> Bool {
        ArchiveFormat.match(url.lastPathComponent)?.entry.singleStream == true
    }
}
