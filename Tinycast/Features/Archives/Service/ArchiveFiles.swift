import Darwin
import Foundation

nonisolated enum ArchiveFiles {
    static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        resolvedParent(lhs).standardizedFileURL.path == resolvedParent(rhs).standardizedFileURL.path
    }

    static func resolvedParent(_ url: URL) -> URL {
        resolvedDirectory(url.deletingLastPathComponent()).appending(path: url.lastPathComponent)
    }

    static func resolvedDirectory(_ url: URL) -> URL {
        guard let path = realpath(url.path, nil) else { return url.resolvingSymlinksInPath() }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    static func supportsExclusiveRename(_ parent: URL) -> Bool {
        let source = parent.appending(path: ".notchcast-probe-\(UUID().uuidString)")
        let target = parent.appending(path: ".notchcast-probe-\(UUID().uuidString)")
        guard mkdir(source.path, 0o700) == 0 else { return false }
        defer { _ = rmdir(source.path); _ = rmdir(target.path) }
        return renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0
    }
    static func quarantine(_ archive: URL) throws -> Data? {
        let size = getxattr(archive.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        if size < 0 {
            if errno == ENOATTR { return nil }
            throw ArchiveFailure.filesystem("quarantine read: \(errno)")
        }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes {
            getxattr(archive.path, "com.apple.quarantine", $0.baseAddress, size, 0, XATTR_NOFOLLOW)
        }
        guard read == size else { throw ArchiveFailure.filesystem("quarantine read: \(errno)") }
        return data
    }

    static func items(_ root: URL) throws -> [URL] {
        var result: [URL] = []
        var folders = [root]
        while let folder = folders.popLast() {
            try Task.checkCancellation()
            for item in try children(folder) {
                result.append(item)
                guard result.count <= 100_000 else { throw ArchiveFailure.tooManyEntries }
                guard let info = try attributesIfPresent(item) else { continue }
                if info.st_mode & S_IFMT == S_IFDIR { folders.append(item) }
            }
        }
        return result
    }

    static func bytes(_ root: URL) throws -> Int64 {
        try items(root).reduce(Int64(0)) { total, item in
            guard let info = try attributesIfPresent(item) else { return total }
            return total + (info.st_mode & S_IFMT == S_IFREG ? info.st_size : 0)
        }
    }

    static func prepare(_ staging: URL, quarantine: Data?) throws -> URL {
        try withAccessibleDirectories(staging) { try prepareContents(staging, quarantine: quarantine) }
    }

    private static func prepareContents(_ staging: URL, quarantine: Data?) throws -> URL {
        let manager = FileManager.default
        let all = try items(staging)
        for item in all.reversed() {
            try Task.checkCancellation()
            if item.lastPathComponent == "__MACOSX" {
                try manager.removeItem(at: item)
            } else if item.lastPathComponent.hasPrefix("._") {
                let partner = item.deletingLastPathComponent().appending(path: String(item.lastPathComponent.dropFirst(2)))
                if exists(partner) { try manager.removeItem(at: item) }
            }
        }
        let top = try children(staging)
        guard !top.isEmpty else { throw ArchiveFailure.invalidListing }
        let root = top.count == 1 ? top[0] : staging
        let boundary = root.resolvingSymlinksInPath().path + "/"
        let remaining = [root] + (try attributes(root).st_mode & S_IFMT == S_IFDIR ? try items(root) : [])
        for item in remaining {
            try Task.checkCancellation()
            let info = try attributes(item)
            switch info.st_mode & S_IFMT {
            case S_IFLNK:
                let target = try manager.destinationOfSymbolicLink(atPath: item.path)
                guard item != root, !target.hasPrefix("/"),
                      item.resolvingSymlinksInPath().path.hasPrefix(boundary) else {
                    throw ArchiveFailure.unsafePath(item.lastPathComponent)
                }
                var depth = item.deletingLastPathComponent().path.dropFirst(root.path.count).split(separator: "/").count
                for component in target.split(separator: "/") {
                    if component == ".." { depth -= 1 } else if component != "." { depth += 1 }
                    guard depth >= 0 else { throw ArchiveFailure.unsafePath(item.lastPathComponent) }
                }
            case S_IFDIR, S_IFREG: break
            default: throw ArchiveFailure.unsafePath(item.lastPathComponent)
            }
            if let quarantine { try apply(quarantine, to: item, info: info) }
        }
        return root
    }

    static func applyQuarantine(_ value: Data?, to item: URL) throws {
        if let value { try apply(value, to: item, info: attributes(item)) }
    }

    private static func apply(_ value: Data, to item: URL, info: stat) throws {
        let writable = info.st_mode & S_IFMT != S_IFLNK && info.st_mode & S_IWUSR == 0
        if writable, chmod(item.path, info.st_mode | S_IWUSR) != 0 {
            throw ArchiveFailure.filesystem("quarantine permission: \(errno)")
        }
        defer { if writable { _ = chmod(item.path, info.st_mode) } }
        let status = value.withUnsafeBytes {
            setxattr(item.path, "com.apple.quarantine", $0.baseAddress, value.count, 0, XATTR_NOFOLLOW)
        }
        guard status == 0 else { throw ArchiveFailure.filesystem("quarantine write: \(errno)") }
    }

    static func publish(
        _ root: URL, staging: URL, archive: URL,
        recovered: Bool = false,
        exclusiveRename: (String, String) -> Int32 = { renamex_np($0, $1, UInt32(RENAME_EXCL)) }
    ) throws -> URL {
        let base = root == staging ? ArchiveFormat.baseName(archive) : root.lastPathComponent
        let isFile = try attributes(root).st_mode & S_IFMT == S_IFREG
        let suffix = isFile || root.pathExtension.lowercased() == "app" ? root.pathExtension : ""
        let stem = suffix.isEmpty ? base : String(base.dropLast(suffix.count + 1))
        for number in 1..<10_000 {
            try Task.checkCancellation()
            let duplicate = recovered ? "\(stem) (recovered)" + (number == 2 ? "" : " \(number - 1)") : "\(stem) (\(number))"
            let name = number == 1 ? base : duplicate + (suffix.isEmpty ? "" : ".\(suffix)")
            let target = archive.deletingLastPathComponent().appending(path: name)
            if root == staging, chmod(root.path, 0o755) != 0 {
                throw ArchiveFailure.filesystem("publish permissions: \(errno)")
            }
            if exclusiveRename(root.path, target.path) == 0 { return target }
            if errno == ENOTSUP {
                if mkdir(target.path, 0o755) == 0 {
                    do {
                        let destination = target.appending(path: root == staging ? "Contents" : root.lastPathComponent)
                        try FileManager.default.moveItem(at: root, to: destination)
                        return destination
                    } catch {
                        throw ArchiveFailure.filesystem("visible recovery at \(target.path): \(error)")
                    }
                }
            }
            guard errno == EEXIST else { throw ArchiveFailure.filesystem("publish: \(errno)") }
        }
        throw ArchiveFailure.filesystem("publish: exhausted names")
    }

    static func attributes(_ url: URL) throws -> stat {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw ArchiveFailure.filesystem("stat: \(errno)") }
        return info
    }

    private static func attributesIfPresent(_ url: URL) throws -> stat? {
        var info = stat()
        if lstat(url.path, &info) == 0 { return info }
        if errno == ENOENT { return nil }
        throw ArchiveFailure.filesystem("stat: \(errno)")
    }

    private static func children(_ folder: URL) throws -> [URL] {
        guard let directory = opendir(folder.path) else {
            if errno == ENOENT { return [] }
            throw ArchiveFailure.filesystem("opendir: \(errno)")
        }
        defer { closedir(directory) }
        var result: [URL] = []
        errno = 0
        while let entry = readdir(directory) {
            let length = Int(entry.pointee.d_namlen) + 1
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: length) { String(cString: $0) }
            }
            if name != ".", name != ".." { result.append(folder.appending(path: name)) }
            errno = 0
        }
        guard errno == 0 else { throw ArchiveFailure.filesystem("readdir: \(errno)") }
        return result
    }

    static func exists(_ url: URL) -> Bool { (try? attributes(url)) != nil }

    static func removeStaging(_ staging: URL) throws {
        guard exists(staging) else { return }
        try withAccessibleDirectories(staging) { try FileManager.default.removeItem(at: staging) }
    }

    private static func withAccessibleDirectories<T>(_ root: URL, body: () throws -> T) throws -> T {
        var modes: [(URL, mode_t)] = []
        defer {
            for (folder, mode) in modes.reversed() where exists(folder) { _ = chmod(folder.path, mode) }
        }
        var folders = [root]
        while let folder = folders.popLast() {
            let info = try attributes(folder)
            guard info.st_mode & S_IFMT == S_IFDIR else { throw ArchiveFailure.unsafePath(folder.lastPathComponent) }
            if info.st_mode & S_IRWXU != S_IRWXU {
                guard chmod(folder.path, info.st_mode | S_IRWXU) == 0 else {
                    throw ArchiveFailure.filesystem("directory permission: \(errno)")
                }
                modes.append((folder, info.st_mode))
            }
            for child in try children(folder) where try attributes(child).st_mode & S_IFMT == S_IFDIR {
                folders.append(child)
            }
        }
        return try body()
    }
}
