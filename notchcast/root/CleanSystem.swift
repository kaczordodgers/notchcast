import Darwin
import Foundation

enum CleanSystem {
    enum Failure: Error { case refused }

    static var policy: CleanSystemPolicy {
        .init(roots: CleanSystemPolicy.allowedRoots, now: .now,
              cacheAge: 30 * 86_400, logAge: 30 * 86_400)
    }

    static func inspect(_ path: String, owner: uid_t? = nil) throws -> CleanSystemEntry {
        guard !path.utf8.contains(0), path.hasPrefix("/"), "/" + path.split(separator: "/").joined(separator: "/") == path,
              !path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." })
        else { throw Failure.refused }
        var current = ""
        var info = stat()
        for component in path.split(separator: "/") {
            current += "/" + component
            guard lstat(current, &info) == 0, info.st_mode & S_IFMT != S_IFLNK
            else { throw Failure.refused }
        }
        guard info.st_mode & S_IFMT != S_IFREG || info.st_nlink == 1 else { throw Failure.refused }
        guard owner == nil || info.st_uid == owner else { throw Failure.refused }
        return .init(path: path, size: info.st_size,
                     modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                        + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000),
                     identity: "\(info.st_dev):\(info.st_ino):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)",
                     isRegularFile: info.st_mode & S_IFMT == S_IFREG, hasSymlinkComponent: false)
    }

    static func validate(_ entry: CleanSystemEntry, policy: CleanSystemPolicy) throws {
        guard policy.reason(for: entry) != nil, try inspect(entry.path) == entry
        else { throw Failure.refused }
    }

    static func run(_ command: RootContract.Command) throws -> Data {
        if command == .cleanSystemList {
            var entries: [CleanSystemEntry] = []
            var seen = Set<String>()
            for root in policy.roots {
                guard let walker = FileManager().enumerator(atPath: root.path) else { continue }
                while let relative = walker.nextObject() as? String {
                    let path = root.path + "/" + relative
                    guard let entry = try? inspect(path, owner: 0) else { walker.skipDescendants(); continue }
                    guard let parent = try? directory((path as NSString).deletingLastPathComponent,
                                                      owner: 0, protected: true) else { continue }
                    close(parent)
                    if policy.reason(for: entry) != nil, seen.insert(path).inserted { entries.append(entry) }
                }
            }
            return try JSONEncoder().encode(entries)
        }
        var data = Data()
        while data.count <= 4096 {
            let chunk = try FileHandle.standardInput.read(upToCount: 4097 - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= 4096, String(bytes: data, encoding: .utf8) != nil
        else { throw Failure.refused }
        let entry = try JSONDecoder().decode(CleanSystemEntry.self, from: data)
        try validate(entry, policy: policy)
        guard let rawUID = ProcessInfo.processInfo.environment["SUDO_UID"],
              let uid = uid_t(rawUID), uid != 0, let user = getpwuid(uid)
        else { throw Failure.refused }
        let trash = String(cString: user.pointee.pw_dir) + "/.Trash"
        try Self.trash(entry, policy: policy, destination: trash, owner: uid, sourceOwner: 0)
        return Data(command.output.utf8)
    }

    static func trash(_ entry: CleanSystemEntry, policy: CleanSystemPolicy,
                      destination trash: String, owner: uid_t, sourceOwner: uid_t) throws {
        try validate(entry, policy: policy)
        let destination = try directory(trash, owner: owner, protected: false)
        defer { close(destination) }
        let source = try directory((entry.path as NSString).deletingLastPathComponent,
                                   owner: sourceOwner, protected: true)
        defer { close(source) }
        var info = stat()
        guard fstatat(source, (entry.path as NSString).lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
              matches(info, entry: entry, owner: sourceOwner) else { throw Failure.refused }
        let name = UUID().uuidString + "-" + (entry.path as NSString).lastPathComponent
        guard renameatx_np(source, (entry.path as NSString).lastPathComponent,
                           destination, name, UInt32(RENAME_EXCL)) == 0 else { throw Failure.refused }
    }

    static func matches(_ info: stat, entry: CleanSystemEntry, owner: uid_t) -> Bool {
        info.st_uid == owner && info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1
            && entry.isRegularFile && !entry.hasSymlinkComponent && info.st_size == entry.size
            && Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000) == entry.modified
            && "\(info.st_dev):\(info.st_ino):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)" == entry.identity
    }

    static func acceptsParent(_ info: stat, owner: uid_t) -> Bool {
        guard info.st_uid == 0 || info.st_uid == owner else { return false }
        if info.st_mode & 0o022 == 0 { return true }
        guard info.st_uid == 0 else { return false }
        if info.st_mode & 0o002 != 0 { return info.st_mode & S_ISVTX != 0 }
        // admin, and _analyticsusers for /Library/Logs/DiagnosticReports.
        return [80, 250].contains(info.st_gid)
    }

    private static func directory(_ path: String, owner: uid_t, protected: Bool) throws -> Int32 {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.refused }
        do {
            for component in path.split(separator: "/") {
                let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw Failure.refused }
                close(descriptor)
                descriptor = next
                if protected {
                    var info = stat()
                    guard fstat(descriptor, &info) == 0, acceptsParent(info, owner: owner)
                    else { throw Failure.refused }
                }
            }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_uid == owner else { throw Failure.refused }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }
}
