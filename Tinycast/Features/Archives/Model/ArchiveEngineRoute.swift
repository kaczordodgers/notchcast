import Foundation

nonisolated enum ArchiveEngineRoute: Equatable, Sendable {
    case hatchzip
    case bsdtar
    case zstd
    case xad

    static func route(_ url: URL, windowsZIP: Bool = false) -> Self? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") { return windowsZIP ? .xad : .hatchzip }
        if [".7z", ".rar", ".tar", ".tgz", ".tar.gz", ".001"].contains(where: name.hasSuffix)
            || name.range(of: #"\.r[0-9]{2}$"#, options: .regularExpression) != nil { return .hatchzip }
        if [".zst", ".tzst"].contains(where: name.hasSuffix) { return .zstd }
        if [".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".gz", ".xz", ".bz2", ".iso", ".cab", ".pkg", ".xar", ".cpio"]
            .contains(where: name.hasSuffix) { return .bsdtar }
        if [".sit", ".sitx", ".lzh", ".lha", ".arj", ".z", ".arc", ".zoo"].contains(where: name.hasSuffix) { return .xad }
        return nil
    }

    static func isSingleStream(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".gz", ".xz", ".bz2", ".zst"].contains(where: name.hasSuffix)
            && ![".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst"].contains(where: name.hasSuffix)
    }
}
