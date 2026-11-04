import Foundation

nonisolated enum ArchiveFormat {
    static let typeIdentifiers = [
        "public.zip-archive", "org.7-zip.7-zip-archive", "com.rarlab.rar-archive",
        "public.tar-archive", "org.gnu.gnu-zip-tar-archive", "org.gnu.gnu-zip-archive", "app.notchcast.split-archive"
    ]

    static func accepts(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".zip", ".7z", ".rar", ".tar", ".tgz", ".tar.gz", ".001"].contains { name.hasSuffix($0) }
            || name.range(of: #"\.r[0-9]{2}$"#, options: .regularExpression) != nil
    }

    static func baseName(_ url: URL) -> String {
        var name = url.lastPathComponent
        if name.lowercased().hasSuffix(".001") { name = String(name.dropLast(4)) }
        name = name.replacingOccurrences(
            of: #"(?i)(\.part[0-9]+\.rar|\.tar\.gz|\.tgz|\.zip|\.7z|\.rar|\.tar|\.r[0-9]{2})$"#,
            with: "", options: .regularExpression)
        return name.isEmpty || name == "." || name == ".." ? "Archive" : name
    }
}
