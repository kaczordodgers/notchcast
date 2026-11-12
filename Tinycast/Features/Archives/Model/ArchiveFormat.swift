import Foundation

nonisolated enum ArchiveFormat {
    struct Entry {
        let suffix: String
        let identifier: String
        let route: ArchiveEngineRoute
        var defaultOrder: Int?
        var singleStream = false
    }

    static let entries: [Entry] = [
        .init(suffix: "zip", identifier: "public.zip-archive", route: .hatchzip, defaultOrder: 2),
        .init(suffix: "7z", identifier: "org.7-zip.7-zip-archive", route: .hatchzip, defaultOrder: 3),
        .init(suffix: #"(?:part[0-9]+\.)?rar|r[0-9]{2}"#, identifier: "com.rarlab.rar-archive", route: .hatchzip, defaultOrder: 0),
        .init(suffix: "tar", identifier: "public.tar-archive", route: .hatchzip, defaultOrder: 4),
        .init(suffix: #"tar\.gz|tgz"#, identifier: "org.gnu.gnu-zip-tar-archive", route: .hatchzip, defaultOrder: 5),
        .init(suffix: "gz", identifier: "org.gnu.gnu-zip-archive", route: .bsdtar, defaultOrder: 6, singleStream: true),
        .init(suffix: "001", identifier: "app.notchcast.split-archive", route: .hatchzip, defaultOrder: 1),
        .init(suffix: "xz", identifier: "org.tukaani.xz-archive", route: .bsdtar, defaultOrder: 7, singleStream: true),
        .init(suffix: #"tar\.xz|txz"#, identifier: "org.tukaani.tar-xz-archive", route: .bsdtar, defaultOrder: 8),
        .init(suffix: "bz2", identifier: "public.bzip2-archive", route: .bsdtar, defaultOrder: 9, singleStream: true),
        .init(suffix: #"tar\.bz2|tbz2"#, identifier: "public.tar-bzip2-archive", route: .bsdtar, defaultOrder: 10),
        .init(suffix: "zst", identifier: "app.notchcast.zstd-archive", route: .zstd, singleStream: true),
        .init(suffix: #"tar\.zst|tzst"#, identifier: "app.notchcast.zstd-tar-archive", route: .zstd),
        .init(suffix: "iso", identifier: "public.iso-image", route: .bsdtar),
        .init(suffix: "cab", identifier: "com.microsoft.cab", route: .bsdtar),
        .init(suffix: "pkg", identifier: "com.apple.installer-package-archive", route: .bsdtar),
        .init(suffix: "xar", identifier: "com.apple.xar-archive", route: .bsdtar),
        .init(suffix: "cpio", identifier: "public.cpio-archive", route: .bsdtar, defaultOrder: 11),
        .init(suffix: "sit", identifier: "com.stuffit.archive.sit", route: .xad),
        .init(suffix: "sitx", identifier: "com.stuffit.archive.sitx", route: .xad),
        .init(suffix: "lzh|lha", identifier: "app.notchcast.lzh-archive", route: .xad),
        .init(suffix: "arj", identifier: "app.notchcast.arj-archive", route: .xad),
        .init(suffix: "z", identifier: "public.z-archive", route: .xad, defaultOrder: 12),
        .init(suffix: "arc", identifier: "app.notchcast.arc-archive", route: .xad),
        .init(suffix: "zoo", identifier: "app.notchcast.zoo-archive", route: .xad)
    ]

    static let typeIdentifiers = entries.map(\.identifier)
    static let defaultTypeIdentifiers = entries.compactMap { entry in
        entry.defaultOrder.map { (order: $0, identifier: entry.identifier) }
    }.sorted { $0.order < $1.order }.map(\.identifier)

    static func match(_ name: String) -> (entry: Entry, range: Range<String.Index>)? {
        entries.compactMap { entry in
            name.range(of: "\\.(?:\(entry.suffix))$", options: [.regularExpression, .caseInsensitive])
                .map { (entry: entry, range: $0) }
        }.min { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func accepts(_ url: URL) -> Bool { match(url.lastPathComponent) != nil }

    static func baseName(_ url: URL) -> String {
        var name = url.lastPathComponent
        if name.lowercased().hasSuffix(".001") { name = String(name.dropLast(4)) }
        if let match = match(name), match.entry.suffix != "001" { name = String(name[..<match.range.lowerBound]) }
        return name.isEmpty || name == "." || name == ".." ? "Archive" : name
    }
}
