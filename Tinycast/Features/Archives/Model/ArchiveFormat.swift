import Foundation

nonisolated enum ArchiveFormat {
    static let typeIdentifiers = [
        "public.zip-archive", "org.7-zip.7-zip-archive", "com.rarlab.rar-archive",
        "public.tar-archive", "org.gnu.gnu-zip-tar-archive", "org.gnu.gnu-zip-archive", "app.notchcast.split-archive",
        "org.tukaani.xz-archive", "org.tukaani.tar-xz-archive", "public.bzip2-archive", "public.tar-bzip2-archive",
        "app.notchcast.zstd-archive", "app.notchcast.zstd-tar-archive", "public.iso-image", "com.microsoft.cab",
        "com.apple.installer-package-archive", "com.apple.xar-archive", "public.cpio-archive",
        "com.stuffit.archive.sit", "com.stuffit.archive.sitx", "app.notchcast.lzh-archive", "app.notchcast.arj-archive",
        "public.z-archive", "app.notchcast.arc-archive", "app.notchcast.zoo-archive"
    ]

    static let defaultTypeIdentifiers = [
        "com.rarlab.rar-archive", "app.notchcast.split-archive",
        "public.zip-archive", "org.7-zip.7-zip-archive", "public.tar-archive",
        "org.gnu.gnu-zip-tar-archive", "org.gnu.gnu-zip-archive", "org.tukaani.xz-archive",
        "org.tukaani.tar-xz-archive", "public.bzip2-archive", "public.tar-bzip2-archive",
        "public.cpio-archive", "public.z-archive"
    ]

    static func accepts(_ url: URL) -> Bool {
        ArchiveEngineRoute.route(url) != nil
    }

    static func baseName(_ url: URL) -> String {
        var name = url.lastPathComponent
        if name.lowercased().hasSuffix(".001") { name = String(name.dropLast(4)) }
        name = name.replacingOccurrences(
            of: #"(?i)(\.part[0-9]+\.rar|\.tar\.(gz|xz|bz2|zst)|\.tgz|\.txz|\.tbz2|\.tzst|\.zip|\.7z|\.rar|\.tar|\.r[0-9]{2}|"#
                + #"\.gz|\.xz|\.bz2|\.zst|\.iso|\.cab|\.pkg|\.xar|\.cpio|\.sitx?|\.lzh|\.lha|\.arj|\.z|\.arc|\.zoo)$"#,
            with: "", options: .regularExpression)
        return name.isEmpty || name == "." || name == ".." ? "Archive" : name
    }
}
